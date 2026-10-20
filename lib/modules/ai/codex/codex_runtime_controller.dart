import 'package:flutter/foundation.dart';

import '../../../utils/version_utils.dart';
import '../agent_config.dart';
import '../runtime/agent_options.dart';
import '../runtime/agent_runtime.dart';
import 'codex_account_service.dart';
import 'codex_app_server.dart';
import 'codex_environment.dart';
import 'codex_installer.dart';
import 'codex_types.dart';

/// Codex 运行环境（[AgentRuntime] 的实现）：已安装版本、最新版本、安装/升级进度，
/// 以及各 Codex Agent 的账号与模型（[accounts]）。
///
/// 全局单例（由 AppServices 创建），关闭 Agent 编辑框不会中断下载。
class CodexRuntimeController extends ChangeNotifier implements AgentRuntime {
  CodexRuntimeController({Future<CodexEnvironment> Function()? environment, CodexAppServer? server})
    : _environment = environment ?? CodexEnvironment.current,
      _custom = server,
      accounts = CodexAccountService(server: server);

  final Future<CodexEnvironment> Function() _environment;
  final CodexAppServer? _custom;

  /// 未指定时使用全局实例（使用时再取，测试可替换全局实例）
  CodexAppServer get _server => _custom ?? CodexAppServer.shared;

  /// 账号、登录与模型列表
  final CodexAccountService accounts;

  @override
  String? installedVersion;

  @override
  String? latestVersion;

  @override
  bool loaded = false;

  /// 当前安装阶段，未在安装时为 null
  CodexInstallStage? stage;

  @override
  double? progress;

  @override
  String? error;

  Future<bool>? _installing;
  DateTime? _latestCheckedAt;

  /// 最新版本缓存时间：GitHub 未登录的接口每小时限 60 次，避免每次打开编辑框都查询
  static const latestCacheDuration = Duration(minutes: 30);

  @override
  String get displayName => 'Codex';

  @override
  String get notInstalledKey => 'codex.not_installed.desc';

  @override
  bool get installed => installedVersion != null;

  @override
  bool get busy => stage != null;

  @override
  String? get stageKey => switch (stage) {
    null => null,
    CodexInstallStage.checking => 'codex.stage.checking',
    CodexInstallStage.downloading => 'codex.stage.downloading',
    CodexInstallStage.verifying => 'codex.stage.verifying',
  };

  @override
  Map<String, Object?> get stageArgs => {'version': latestVersion ?? ''};

  @override
  bool get updateAvailable =>
      installed && latestVersion != null && VersionUtils.compare(latestVersion!, installedVersion!) > 0;

  /// 创建安装器（测试时可替换下载地址）
  @protected
  Future<CodexInstaller> createInstaller() async => CodexInstaller(await _environment());

  @override
  Future<void> loadLocal() async {
    try {
      installedVersion = (await _environment()).version;
    } catch (_) {
      // 数据目录不可用：按未安装显示
      installedVersion = null;
    }
    loaded = true;
    notifyListeners();
  }

  @override
  Future<void> checkUpdate({bool force = false}) async {
    await loadLocal();
    final now = DateTime.now();
    if (busy || (!force && _latestCheckedAt != null && now.difference(_latestCheckedAt!) < latestCacheDuration)) {
      return;
    }
    CodexInstaller? installer;
    try {
      installer = await createInstaller();
      latestVersion = (await installer.latestRelease()).version;
      _latestCheckedAt = now;
      if (force) error = null;
    } catch (e) {
      // 自动检测失败不提示，只是不显示升级；手动检测失败显示原因
      if (force) error = '$e';
    } finally {
      installer?.dispose();
    }
    notifyListeners();
  }

  @override
  Future<bool> install() => _installing ??= _doInstall().whenComplete(() => _installing = null);

  Future<bool> _doInstall() async {
    error = null;
    progress = null;
    _setStage(CodexInstallStage.checking);
    CodexInstaller? installer;
    try {
      installer = await createInstaller();
      await installer.cleanStaging();
      final release = await installer.latestRelease();
      latestVersion = release.version;
      _latestCheckedAt = DateTime.now();
      _setStage(CodexInstallStage.downloading);
      installedVersion = await installer.install(
        release,
        onProgress: (received, total) {
          final value = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
          // 进度每变化 1% 才刷新界面
          if (value == null || progress == null || (value - progress!).abs() >= 0.01 || value == 1) {
            progress = value;
            notifyListeners();
          }
        },
        onVerifying: () {
          progress = null;
          _setStage(CodexInstallStage.verifying);
        },
        // 替换运行包前结束正在运行的 Codex
        beforeReplace: _server.shutdown,
      );
      return true;
    } catch (e) {
      error = '$e';
      installedVersion = installer?.env.version;
      return false;
    } finally {
      installer?.dispose();
      stage = null;
      progress = null;
      notifyListeners();
    }
  }

  @override
  Future<void> uninstall() async {
    if (busy) return;
    await _server.shutdown();
    CodexInstaller? installer;
    try {
      installer = await createInstaller();
      await installer.uninstall();
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      installer?.dispose();
    }
    installedVersion = installer?.env.version;
    notifyListeners();
  }

  /// 删除 Agent 的 CODEX_HOME（登录凭据与会话记录）；尽力而为，失败时忽略
  @override
  Future<void> removeAgentData(String agentUuid) async {
    try {
      await _server.restart(agentUuid);
      await (await _environment()).removeHome(agentUuid);
    } catch (_) {
      // 数据目录不可用：没有可删除的数据
    }
  }

  /// 模型列表来自该 Agent 的 app-server（model/list），每个模型有自己支持的推理强度
  @override
  Future<AgentOptions> loadOptions(AgentSettings settings, {bool force = false}) async {
    final models = await accounts.listModels(settings.uuid);
    return AgentOptions([
      for (final m in models)
        AgentModelOption(
          id: m.id,
          label: m.displayName,
          isDefault: m.isDefault,
          efforts: m.efforts,
          defaultEffort: m.defaultEffort,
        ),
    ]);
  }

  void _setStage(CodexInstallStage s) {
    stage = s;
    notifyListeners();
  }
}
