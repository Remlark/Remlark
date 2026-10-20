import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../utils/platform_utils.dart';
import 'platform/codex_platform.dart';

/// Codex 运行环境的目录布局（都在应用数据目录下，不使用也不修改用户自己的 codex 与 ~/.codex）：
///
/// - `codex/runtime`：完整运行包（主程序、执行工具与资源），升级时整包替换；
/// - `codex/homes/<Agent uuid>`：每个 Codex Agent 独立的 CODEX_HOME（登录凭据、会话记录），可登录不同账号；
/// - `codex/workspace`：会话的工作目录（空目录，避免 Codex 读取任何文件或 AGENTS.md）。
class CodexEnvironment {
  CodexEnvironment(this.root, this.platform);

  /// 根目录（`<应用数据目录>/codex`）
  final String root;
  final CodexPlatform platform;

  String get runtimeDir => p.join(root, 'runtime');
  String get workspaceDir => p.join(root, 'workspace');

  /// 运行目录 [runtime] 中的主程序
  String executableIn(String runtime) => p.join(runtime, 'bin', platform.executableName);

  /// 运行目录 [runtime] 中的执行工具
  String codeModeHostIn(String runtime) => p.join(runtime, 'bin', platform.codeModeHostName);

  /// 主程序路径
  String get executable => executableIn(runtimeDir);

  /// 是否可以启动 Codex
  bool get installed => File(executable).existsSync() && File(codeModeHostIn(runtimeDir)).existsSync();

  /// 已安装的版本（读取运行包中的 codex-package.json，不启动进程），未安装返回 null
  String? get version => installed ? packageVersion(runtimeDir) : null;

  /// 运行目录 [runtime] 中运行包清单记录的版本，读取失败返回 null
  static String? packageVersion(String runtime) {
    try {
      final j = jsonDecode(File(p.join(runtime, 'codex-package.json')).readAsStringSync());
      final v = (j as Map<String, dynamic>)['version'];
      return v is String && v.isNotEmpty ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Agent [homeId] 的 CODEX_HOME
  String homeDir(String homeId) => p.join(root, 'homes', homeId);

  /// 运行 Codex 子进程的环境变量：继承当前环境，指定该 Agent 的 CODEX_HOME
  Map<String, String> processEnvironment(String homeId) => {...Platform.environment, 'CODEX_HOME': homeDir(homeId)};

  /// 被关闭的功能：本机命令、文件修改、插件、子 Agent、浏览器 / 电脑操作等。
  /// 终端助手只通过 Remlark 的终端操作协议在用户的终端里执行命令，Codex 只负责思考下一步并按 JSON 协议回复，
  /// 不能碰用户自己的电脑，也不调用其他工具（否则会浪费轮次）。
  /// 用 `-c features.<名称>=false` 传入：新版本中不存在的名称只会被忽略，不会导致启动失败
  static const disabledFeatures = [
    'shell_tool',
    'unified_exec',
    'apps',
    'plugins',
    'multi_agent',
    'image_generation',
    'browser_use',
    'computer_use',
    'goals',
    'view_image',
    'hooks',
    'skill_search',
    'tool_suggest',
    'sleep_tool',
    'memories',
  ];

  /// 启动 app-server 的参数（标准输入输出上的 JSON-RPC）
  static List<String> get appServerArgs => [
    'app-server',
    '--listen',
    'stdio://',
    '-c',
    'web_search="disabled"',
    for (final f in disabledFeatures) ...['-c', 'features.$f=false'],
  ];

  /// 创建 CODEX_HOME（保存登录凭据，仅当前用户可访问）与工作目录
  Future<void> prepare(String homeId) async {
    final home = Directory(homeDir(homeId));
    if (!await home.exists()) {
      await home.create(recursive: true);
      await PlatformUtils.restrictDirectory(home.path);
    }
    await Directory(workspaceDir).create(recursive: true);
  }

  /// 删除 Agent 的 CODEX_HOME（Agent 被删除或放弃新建时调用），失败时忽略
  Future<void> removeHome(String homeId) async {
    if (homeId.isEmpty) return;
    try {
      final home = Directory(homeDir(homeId));
      if (await home.exists()) await home.delete(recursive: true);
    } catch (_) {
      // 文件被占用等情况下保留，不影响其他 Agent
    }
  }

  /// 登录凭据文件名（Codex 把凭据以文件保存在 CODEX_HOME 中）
  static const authFileName = 'auth.json';

  /// 采用临时目录 [fromHome] 中刚完成的登录：把凭据替换到 Agent [toHome]，然后删除临时目录。
  ///
  /// 登录先在临时目录中进行（与 GitAstra 相同），登录进程不占用 Agent 自己的目录，取消或失败时原登录不受影响。
  /// 只替换凭据文件，会话记录等数据保持不变；先写临时文件再改名覆盖，替换中断不会留下不完整的凭据
  Future<void> adoptLogin(String fromHome, String toHome) async {
    final source = File(p.join(homeDir(fromHome), authFileName));
    if (!await source.exists()) throw StateError('auth.json');
    await prepare(toHome);
    final target = p.join(homeDir(toHome), authFileName);
    final temp = await source.copy('$target.tmp');
    // 凭据只允许当前用户读写（与 Codex 自己写入的权限一致）
    await PlatformUtils.restrictPermissions(temp.path);
    await temp.rename(target);
    await removeHome(fromHome);
  }

  /// 生成临时登录目录名：前缀 + 时间戳 + 随机数
  static String newStagingHomeId() {
    final random = Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '.login-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-$random';
  }

  static Future<CodexEnvironment>? _current;

  /// 测试时替换为临时目录
  @visibleForTesting
  static set override(CodexEnvironment? env) => _current = env == null ? null : Future.value(env);

  /// 当前应用使用的目录布局（首次调用时解析应用数据目录，之后复用）
  static Future<CodexEnvironment> current() {
    return _current ??= () async {
      final data = await PlatformUtils.dataDir();
      return CodexEnvironment(p.join(data.path, 'codex'), CodexPlatform.current());
    }();
  }
}
