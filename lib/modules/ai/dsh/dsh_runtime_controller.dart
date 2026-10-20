import 'package:flutter/foundation.dart';

import '../../../utils/version_utils.dart';
import '../agent_config.dart';
import '../runtime/agent_options.dart';
import '../runtime/agent_runtime.dart';
import 'dsh_acp_service.dart';
import 'dsh_environment.dart';
import 'dsh_installer.dart';
import 'dsh_types.dart';

/// dsh 运行环境（[AgentRuntime] 的实现）：已安装版本、最新版本、安装/升级进度。
///
/// 全局单例（由 AppServices 创建），关闭 Agent 编辑框不会中断下载。
class DshRuntimeController extends ChangeNotifier implements AgentRuntime {
  DshRuntimeController({Future<DshEnvironment> Function()? environment, DshAcpService? service})
    : _environment = environment ?? DshEnvironment.current,
      _service = service ?? DshAcpService.shared;

  final Future<DshEnvironment> Function() _environment;
  final DshAcpService _service;

  /// 已安装的 dsh 版本，未安装为 null
  @override
  String? installedVersion;

  /// npm 上的最新版本，尚未查询或查询失败为 null
  @override
  String? latestVersion;

  /// 是否已读取过本地安装状态
  @override
  bool loaded = false;

  /// 当前安装阶段，未在安装时为 null
  DshInstallStage? stage;

  /// 下载进度（0~1），未知时为 null
  @override
  double? progress;

  /// 正在安装的版本（Node.js 或 dsh，随阶段变化）
  String? stageVersion;

  /// 最近一次安装或查询失败的原因
  @override
  String? error;

  Future<bool>? _installing;
  DateTime? _latestCheckedAt;

  /// 最新版本缓存时间，避免每次打开设置页都请求 npm
  static const latestCacheDuration = Duration(minutes: 30);

  @override
  String get displayName => 'DeepSeek Harness';

  @override
  String get notInstalledKey => 'dsh.not_installed.desc';

  @override
  bool get installed => installedVersion != null;

  @override
  bool get busy => stage != null;

  @override
  String? get stageKey => switch (stage) {
    null => null,
    DshInstallStage.checking => 'dsh.stage.checking',
    DshInstallStage.downloadingNode => 'dsh.stage.node',
    DshInstallStage.installingDsh => 'dsh.stage.dsh',
    DshInstallStage.verifying => 'dsh.stage.verifying',
  };

  @override
  Map<String, Object?> get stageArgs => {'version': stageVersion ?? ''};

  /// 是否有可升级的新版本
  @override
  bool get updateAvailable =>
      installed && latestVersion != null && VersionUtils.compare(latestVersion!, installedVersion!) > 0;

  /// 创建安装器（测试时可替换下载地址）
  @protected
  Future<DshInstaller> createInstaller() async => DshInstaller(await _environment());

  /// 只读取本机安装的版本，不联网
  @override
  Future<void> loadLocal() async {
    try {
      installedVersion = (await _environment()).dshVersion;
    } catch (e) {
      // 数据目录不可用：按未安装显示
      installedVersion = null;
    }
    loaded = true;
    notifyListeners();
  }

  /// 读取本机版本并检测更新：缓存过期或 [force] 时查询 npm 最新版本
  /// （自动检测失败不提示，只是不显示升级；手动检测失败显示原因）
  @override
  Future<void> checkUpdate({bool force = false}) async {
    await loadLocal();
    final now = DateTime.now();
    if (busy || (!force && _latestCheckedAt != null && now.difference(_latestCheckedAt!) < latestCacheDuration)) {
      return;
    }
    DshInstaller? installer;
    try {
      installer = await createInstaller();
      latestVersion = await installer.latestDshVersion();
      _latestCheckedAt = now;
      if (force) error = null;
    } catch (e) {
      if (force) error = '$e';
    } finally {
      installer?.dispose();
    }
    notifyListeners();
  }

  /// 安装或升级到最新版本（Node.js 缺失或过旧时一并安装）。成功返回 true，失败原因见 [error]。
  /// 重复调用时共用同一次安装
  @override
  Future<bool> install() => _installing ??= _doInstall().whenComplete(() => _installing = null);

  Future<bool> _doInstall() async {
    error = null;
    progress = null;
    _setStage(DshInstallStage.checking, null);
    DshInstaller? installer;
    try {
      installer = await createInstaller();
      await installer.cleanStaging();
      final dshVersion = await installer.latestDshVersion();
      latestVersion = dshVersion;
      _latestCheckedAt = DateTime.now();
      final nodeVersion = await installer.latestNodeVersion();
      if (installer.nodeNeedsInstall(nodeVersion)) {
        _setStage(DshInstallStage.downloadingNode, nodeVersion);
        // 替换 Node.js 前结束正在运行的 dsh
        await _service.shutdown();
        await installer.installNode(
          nodeVersion,
          onProgress: (received, total) {
            final value = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
            // 进度每变化 1% 才刷新界面
            if (value == null || progress == null || (value - progress!).abs() >= 0.01 || value == 1) {
              progress = value;
              notifyListeners();
            }
          },
        );
      }
      progress = null;
      _setStage(DshInstallStage.installingDsh, dshVersion);
      installedVersion = await installer.installDsh(dshVersion, beforeReplace: _service.shutdown);
      return true;
    } catch (e) {
      error = '$e';
      installedVersion = installer?.env.dshVersion;
      return false;
    } finally {
      installer?.dispose();
      stage = null;
      progress = null;
      stageVersion = null;
      notifyListeners();
    }
  }

  /// 移除运行环境（保留会话记录）
  @override
  Future<void> uninstall() async {
    if (busy) return;
    await _service.shutdown();
    DshInstaller? installer;
    try {
      installer = await createInstaller();
      await installer.uninstall();
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      installer?.dispose();
    }
    installedVersion = installer?.env.dshVersion;
    notifyListeners();
  }

  /// dsh 的会话记录由所有 Agent 共用，没有单个 Agent 的专属数据
  @override
  Future<void> removeAgentData(String agentUuid) async {}

  /// 模型与推理强度来自 dsh 会话公布的配置项（每个 API Key 读取一次并缓存）
  @override
  Future<AgentOptions> loadOptions(AgentSettings settings, {bool force = false}) =>
      _service.options(settings.apiKey, force: force);

  void _setStage(DshInstallStage s, String? version) {
    stage = s;
    stageVersion = version;
    notifyListeners();
  }
}
