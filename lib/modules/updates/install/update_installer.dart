import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../utils/platform_utils.dart';
import '../../../utils/version_utils.dart';
import '../../settings/settings_repository.dart';
import '../platform/update_platform.dart';
import '../update_release.dart';
import 'install_plan.dart';

/// 管理安装暂存和外部助手握手，不在主进程里覆盖可执行文件。
class UpdateInstaller {
  UpdateInstaller(this.platform);
  final UpdatePlatform platform;
  static const pendingKey = 'updates.pending_install';

  /// 每次升级独立暂存目录，避免失败重试复用未校验文件。
  Future<Directory> createStage() async {
    final base = await PlatformUtils.dataDir();
    final root = await Directory(p.join(base.path, 'updates'))
        .create(recursive: true);
    final stage = await root.createTemp('install-');
    await PlatformUtils.restrictDirectory(stage.path);
    return stage;
  }

  /// 生成当前平台安装计划，开发构建不应替换开发工具或未知应用目录。
  Future<InstallPlan> prepare(Directory stage, File archive, String version) =>
      platform.prepare(
        InstallContext(
          directory: stage,
          archive: archive,
          version: version,
          executable: Platform.resolvedExecutable,
          processId: pid,
        ),
      );

  /// 等待系统授权和助手就绪；授权取消或启动失败时当前应用继续运行。
  Future<void> handoff(InstallPlan plan) async {
    await Process.start(
      plan.executable,
      plan.arguments,
      workingDirectory: plan.directory.path,
      mode: ProcessStartMode.detached,
    );
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      if (await plan.result.exists()) {
        throw const UpdateFailure('updates.error.install');
      }
      if (await plan.ready.exists()) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await abort(plan);
    throw const UpdateFailure('updates.error.permission');
  }

  /// 明确的提交标志防止助手把崩溃或普通退出误当作升级授权。
  Future<void> commit(InstallPlan plan) =>
      File(p.join(plan.directory.path, 'commit')).writeAsString('commit');

  /// 退出失败或授权超时撤销提交，助手必须保留原程序。
  Future<void> abort(InstallPlan plan) =>
      File(p.join(plan.directory.path, 'abort')).writeAsString('abort');

  /// 新启动核对实际版本，再清理属于本次升级的暂存和可写备份；失败保留恢复材料。
  Future<String?> consumeResult(
    SettingsRepository settings,
    String current,
  ) async {
    final pending = await settings.getJson(pendingKey);
    final path = pending['path'];
    final expected = pending['version'];
    if (path is! String || expected is! String) return null;
    // 数据库中的路径也要限制在应用自己的升级目录中。
    final root = p.join((await PlatformUtils.dataDir()).path, 'updates');
    if (!p.isWithin(root, path)) {
      await settings.remove(pendingKey);
      return 'updates.error.install';
    }
    final stage = Directory(path);
    final result = File(p.join(path, 'result'));
    final success =
        await result.exists() &&
        (await result.readAsString()).trim() == 'success' &&
        current != 'development' &&
        VersionUtils.compare(current, expected) == 0;
    if (!success) {
      if (await stage.exists()) {
        await File(p.join(path, 'abort')).writeAsString('abort');
      }
      await settings.remove(pendingKey);
      return 'updates.error.install';
    }
    await settings.remove(pendingKey);
    // 只有成功启动了预期版本才回收旧程序，受保护目录的备份交由管理员处理。
    try {
      final backupFile = File(p.join(path, 'backup'));
      if (await backupFile.exists()) {
        final backup = await backupFile.readAsString();
        if (backup.endsWith('.remlark-backup-${p.basename(path)}')) {
          await Directory(backup).delete(recursive: true);
        }
      }
    } catch (_) {
      /* 安装成功不因备份清理权限不足而误报失败。 */
    }
    // 受保护的旧程序备份不可删除时，仍回收用户可写的下载包与解压目录。
    try {
      await stage.delete(recursive: true);
    } catch (_) {}
    return 'updates.completed';
  }
}
