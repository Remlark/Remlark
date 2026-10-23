import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter/foundation.dart';

import '../../utils/app_version.dart';
import 'install/update_installer.dart';
import 'install/install_plan.dart';
import '../settings/settings_repository.dart';
import 'platform/update_platform.dart';
import 'update_release.dart';
import 'update_service.dart';

/// 更新状态集中管理，切换页面不丢失检查和下载进度。
class UpdatesController extends ChangeNotifier {
  UpdatesController(
    this._settings, {
    UpdateService? service,
    UpdatePlatform? platform,
    UpdateInstaller? installer,
    this.currentVersion = appVersion,
  }) : service = service ?? UpdateService(),
       platform = platform ?? UpdatePlatform.current() {
    this.installer = installer ?? UpdateInstaller(this.platform);
  }
  final SettingsRepository _settings;
  final UpdateService service;
  final UpdatePlatform platform;
  final String currentVersion;
  late final UpdateInstaller installer;
  Future<void> Function()? exitApplication;
  bool installing = false;
  String? outcome;
  bool automatic = true;
  bool checking = false;
  bool downloading = false;
  bool _closed = false;
  Timer? _timer;
  UpdateRelease? release;
  DateTime? checkedAt;
  DateTime? retryAfter;
  String? error;
  int received = 0;
  int total = 0;
  bool get busy => checking || downloading || installing;
  bool get hasUpdate => release?.newerThan(currentVersion) ?? false;
  UpdateAsset? get asset =>
      release?.asset(platform.assetName(release!.version));

  /// 迁移掉旧方案保存的 Token，只保留自动检查偏好和安装结果。
  Future<void> load() async {
    automatic = await _settings.get('updates.automatic') != 'false';
    await _settings.remove('updates.github_token');
    outcome = await installer.consumeResult(_settings, currentVersion);
    if (outcome == 'updates.error.install') error = outcome;
  }

  /// 启动后后台检查，之后每六小时检查一次；网络不阻塞应用启动。
  void start() {
    _timer?.cancel();
    if (!automatic || _closed) return;
    unawaited(check());
    _timer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(check()),
    );
  }

  /// 用户可关闭后台检查，手动检查不受影响。
  Future<void> setAutomatic(bool value) async {
    try {
      await _settings.set('updates.automatic', '$value');
      automatic = value;
      start();
      _notify();
    } catch (_) {
      error = 'updates.error.storage';
      _notify();
    }
  }

  /// 去重检查并限制连续失败重试；保留上次成功版本，失败不显示“已是最新”。
  Future<void> check() async {
    if (busy || _closed) return;
    if (retryAfter != null && DateTime.now().isBefore(retryAfter!)) {
      error = 'updates.error.wait';
      _notify();
      return;
    }
    checking = true;
    error = null;
    _notify();
    try {
      final next = await service.latest();
      release = next;
      checkedAt = DateTime.now();
      retryAfter = null;
    } catch (e) {
      error = e is UpdateFailure ? e.key : 'updates.error.network';
      retryAfter = DateTime.now().add(
        Duration(minutes: error == 'updates.error.forbidden' ? 60 : 1),
      );
    } finally {
      checking = false;
      _notify();
    }
  }

  /// 用户点击升级后串行下载、校验、准备助手并退出安装；后台检查绝不调用此方法。
  Future<void> upgrade() async {
    final selected = asset;
    final selectedRelease = release;
    if (busy || !hasUpdate || selected == null || selectedRelease == null) {
      return;
    }
    if (exitApplication == null || currentVersion == 'development') {
      error = 'updates.error.location';
      _notify();
      return;
    }
    downloading = true;
    received = 0;
    total = selected.size;
    error = null;
    outcome = null;
    InstallPlan? plan;
    Directory? stage;
    _notify();
    try {
      stage = await installer.createStage();
      final archive = File(p.join(stage.path, selected.name));
      await service.download(selectedRelease, selected, archive.path, (
        done,
        size,
      ) {
        received = done;
        total = size > 0 ? size : selected.size;
        _notify();
      });
      downloading = false;
      installing = true;
      _notify();
      plan = await installer.prepare(stage, archive, selectedRelease.version);
      await _settings.setJson(UpdateInstaller.pendingKey, {
        'path': stage.path,
        'version': selectedRelease.version,
      });
      await installer.handoff(plan);
      await installer.commit(plan);
      await exitApplication!();
    } catch (e) {
      // 尚未启动助手的失败可以直接清理，已交接的目录保留供助手和恢复流程使用。
      if (plan == null && stage != null) {
        try {
          await stage.delete(recursive: true);
        } catch (_) {}
      }
      if (plan != null) {
        try {
          await installer.abort(plan);
        } catch (_) {}
      }
      error = e is UpdateFailure
          ? e.key
          : installing
          ? 'updates.error.install'
          : 'updates.error.download';
    } finally {
      downloading = false;
      installing = false;
      _notify();
    }
  }

  /// 异步任务结束时不通知已经释放的界面。
  void _notify() {
    if (!_closed) notifyListeners();
  }

  /// 停止定时器并关闭网络连接，已交接的外部安装助手独立运行。
  @override
  void dispose() {
    _closed = true;
    _timer?.cancel();
    service.close();
    super.dispose();
  }
}
