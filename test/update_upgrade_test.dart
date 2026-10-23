import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/modules/updates/install/install_plan.dart';
import 'package:remlark/modules/updates/install/update_installer.dart';
import 'package:remlark/modules/updates/platform/update_platform.dart';
import 'package:remlark/modules/updates/update_release.dart';
import 'package:remlark/modules/updates/update_service.dart';
import 'package:remlark/modules/updates/updates_controller.dart';
import 'package:remlark/utils/platform_utils.dart';

/// 假网络只写入隔离文件，以验证升级控制器的动作顺序。
class _Service extends UpdateService {
  _Service(this.events, this.release);
  final List<String> events;
  final UpdateRelease release;
  bool failDownload = false;
  Completer<void>? gate;

  /// 返回确定的新版本，不联网。
  @override
  Future<UpdateRelease> latest() async => release;

  /// 模拟校验后的下载交付。
  @override
  Future<void> download(
    UpdateRelease release,
    UpdateAsset asset,
    String destination,
    void Function(int, int) progress,
  ) async {
    events.add('download');
    await gate?.future;
    if (failDownload) throw const UpdateFailure('updates.error.checksum');
    await File(destination).writeAsString('verified');
    progress(8, 8);
    events.add('verified');
  }
}

/// 假安装器只记录动作，不生成或执行任何实际安装进程。
class _Installer extends UpdateInstaller {
  _Installer(super.platform, this.stage, this.events);
  final Directory stage;
  final List<String> events;
  bool failHandoff = false;

  /// 返回测试专用暂存目录。
  @override
  Future<Directory> createStage() async => stage;

  /// 准备必须发生在下载校验之后。
  @override
  Future<InstallPlan> prepare(
    Directory stage,
    File archive,
    String version,
  ) async {
    expect(await archive.readAsString(), 'verified');
    events.add('prepare');
    return InstallPlan(executable: 'unused', arguments: [], directory: stage);
  }

  /// 模拟系统授权取消或助手握手成功。
  @override
  Future<void> handoff(InstallPlan plan) async {
    events.add('handoff');
    if (failHandoff) throw const UpdateFailure('updates.error.permission');
  }

  /// 记录提交，但不允许真的退出测试进程。
  @override
  Future<void> commit(InstallPlan plan) async {
    events.add('commit');
    await super.commit(plan);
  }

  /// 失败必须撤销提交。
  @override
  Future<void> abort(InstallPlan plan) async {
    events.add('abort');
    await super.abort(plan);
  }
}

/// 验证点击升级才安装、退出前握手、失败不退出和重启结果确认。
void main() {
  late Directory root;
  late AppDatabase db;
  late SettingsRepository settings;
  late List<String> events;
  late _Service service;
  late _Installer installer;
  late UpdatesController controller;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('remlark-upgrade-flow-');
    PlatformUtils.overrideDataDir(root);
    final stage = await Directory(p.join(root.path, 'updates/install-test'))
        .create(recursive: true);
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
    events = [];
    final platform = UpdatePlatform.current();
    service = _Service(
      events,
      UpdateRelease('1.2.0', '', [
        UpdateAsset(1, platform.assetName('1.2.0')!, 8, null),
      ]),
    );
    installer = _Installer(platform, stage, events);
    controller = UpdatesController(
      settings,
      service: service,
      platform: platform,
      installer: installer,
      currentVersion: '1.0.0+1',
    );
    controller.exitApplication = () async {
      events.add('exit');
    };
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  test('检查不下载，点击后按校验/准备/交接/提交/退出顺序执行且防重复点击', () async {
    await controller.check();
    expect(events, isEmpty);
    service.gate = Completer<void>();
    final upgrading = controller.upgrade();
    await Future<void>.delayed(Duration.zero);
    await controller.upgrade();
    expect(events, ['download']);
    service.gate!.complete();
    await upgrading;
    expect(events, [
      'download',
      'verified',
      'prepare',
      'handoff',
      'commit',
      'exit',
    ]);
    expect(
      (await settings.getJson(UpdateInstaller.pendingKey))['version'],
      '1.2.0',
    );
  });

  test('校验失败不准备安装，不退出当前应用', () async {
    await controller.check();
    service.failDownload = true;
    await controller.upgrade();
    expect(events, ['download']);
    expect(controller.error, 'updates.error.checksum');
    expect(controller.busy, isFalse);
  });

  test('系统授权取消时撤销提交，当前应用继续运行', () async {
    await controller.check();
    installer.failHandoff = true;
    await controller.upgrade();
    expect(events, ['download', 'verified', 'prepare', 'handoff', 'abort']);
    expect(controller.error, 'updates.error.permission');
    expect(
      await File(p.join(installer.stage.path, 'commit')).exists(),
      isFalse,
    );
  });

  test('退出失败时撤销提交，助手不得把普通退出当作安装授权', () async {
    await controller.check();
    controller.exitApplication = () async => throw StateError('cannot close');
    await controller.upgrade();
    expect(events.last, 'abort');
    expect(await File(p.join(installer.stage.path, 'abort')).exists(), isTrue);
    expect(controller.error, 'updates.error.install');
  });

  test('新进程核对实际版本，只有成功启动预期版本才确认升级', () async {
    await settings.setJson(UpdateInstaller.pendingKey, {
      'path': installer.stage.path,
      'version': '1.2.0',
    });
    await File(p.join(installer.stage.path, 'result')).writeAsString('success');
    expect(
      await installer.consumeResult(settings, '1.2.0+5'),
      'updates.completed',
    );
    expect(await settings.get(UpdateInstaller.pendingKey), isNull);
    expect(await installer.stage.exists(), isFalse);
  });

  test('助手成功但启动版本不符时保留恢复目录并报告失败', () async {
    await settings.setJson(UpdateInstaller.pendingKey, {
      'path': installer.stage.path,
      'version': '1.2.0',
    });
    await File(p.join(installer.stage.path, 'result')).writeAsString('success');
    expect(
      await installer.consumeResult(settings, '1.0.0'),
      'updates.error.install',
    );
    expect(await installer.stage.exists(), isTrue);
    expect(await File(p.join(installer.stage.path, 'abort')).exists(), isTrue);
  });
}
