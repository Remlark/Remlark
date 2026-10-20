import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../utils/platform_utils.dart';
import 'platform/dsh_platform.dart';

/// dsh 运行环境的目录布局（都在应用数据目录下，不使用也不修改用户自己安装的 dsh 与 ~/.dsh）：
///
/// - `dsh/node`：私有 Node.js 运行时；
/// - `dsh/runtime`：npm 安装的 `@deepseek-ai/dsh` 及依赖，升级时整包替换；
/// - `dsh/home`：DSH_HOME（profile、会话记录），升级与移除运行环境都保留；
/// - `dsh/workspace`：会话的工作目录（空目录，避免 Agent 读写其他文件）。
class DshEnvironment {
  DshEnvironment(this.root, this.platform);

  /// 根目录（`<应用数据目录>/dsh`）
  final String root;
  final DshPlatform platform;

  /// npm 包名
  static const packageName = '@deepseek-ai/dsh';

  String get nodeDir => p.join(root, 'node');
  String get runtimeDir => p.join(root, 'runtime');
  String get homeDir => p.join(root, 'home');
  String get workspaceDir => p.join(root, 'workspace');

  /// node 可执行文件
  String get nodeExecutable => platform.nodeExecutable(nodeDir);

  /// npm 入口脚本
  String get npmCli => platform.npmCli(nodeDir);

  /// 运行目录 [runtime] 中 dsh 包所在目录
  static String packageDir(String runtime) => p.join(runtime, 'node_modules', '@deepseek-ai', 'dsh');

  /// dsh 入口脚本（由 node 运行，不依赖 .bin 下的 shell 包装）
  String dshEntry([String? runtime]) => _entryOf(runtime ?? runtimeDir);

  /// 读取 dsh 包的 bin 字段得到入口脚本，读取失败时使用已知的 lib/bin.js
  static String _entryOf(String runtime) {
    final dir = packageDir(runtime);
    try {
      final j = jsonDecode(File(p.join(dir, 'package.json')).readAsStringSync()) as Map<String, dynamic>;
      final bin = j['bin'];
      final rel = bin is String ? bin : (bin is Map ? bin['dsh'] : null);
      if (rel is String && rel.isNotEmpty) return p.join(dir, p.normalize(rel));
    } catch (_) {
      // 使用默认入口
    }
    return p.join(dir, 'lib', 'bin.js');
  }

  /// Node.js 是否已安装
  bool get nodeInstalled => File(nodeExecutable).existsSync();

  /// 已安装的 Node.js 版本（读取 node 目录中的标记文件），未安装返回 null
  String? get nodeVersion {
    if (!nodeInstalled) return null;
    try {
      return File(p.join(nodeDir, _versionMark)).readAsStringSync().trim();
    } catch (_) {
      return null;
    }
  }

  /// 安装时写入 node 目录的版本标记文件名
  static const _versionMark = '.remlark-version';

  /// 写入 Node.js 版本标记
  static Future<void> writeNodeVersion(String nodeDir, String version) =>
      File(p.join(nodeDir, _versionMark)).writeAsString(version);

  /// 已安装的 dsh 版本（读取 package.json，不启动进程），未安装返回 null
  String? get dshVersion {
    if (!nodeInstalled) return null;
    try {
      final j = jsonDecode(File(p.join(packageDir(runtimeDir), 'package.json')).readAsStringSync());
      final v = (j as Map<String, dynamic>)['version'];
      return v is String && File(dshEntry()).existsSync() ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 是否可以启动 dsh
  bool get installed => dshVersion != null;

  /// 运行 dsh / npm 子进程的环境变量：继承当前环境，私有 node 放在 PATH 最前面，
  /// 指定 DSH_HOME；[apiKey] 非空时以 DEEPSEEK_API_KEY 传入
  Map<String, String> processEnvironment({String? apiKey}) {
    final env = Map<String, String>.from(Platform.environment);
    final pathKey = env.keys.firstWhere((k) => k.toUpperCase() == 'PATH', orElse: () => 'PATH');
    final path = env[pathKey] ?? '';
    env[pathKey] = path.isEmpty
        ? platform.nodeBinDir(nodeDir)
        : '${platform.nodeBinDir(nodeDir)}${platform.pathSeparator}$path';
    env['DSH_HOME'] = homeDir;
    if (apiKey != null && apiKey.isNotEmpty) env['DEEPSEEK_API_KEY'] = apiKey;
    return env;
  }

  /// 启动时附加的 profile 补丁：关闭 dsh 在本机执行命令、读写文件、切换目录、派生子 Agent 的工具。
  /// 终端助手只通过 Remlark 的终端操作协议在用户的终端里执行命令，不能碰用户自己的电脑
  String get patchFile => p.join(homeDir, 'remlark.patch.yml');

  /// 被关闭的工具插件 id（dsh-base 中的条目）：本机命令与文件工具，以及网络搜索 / 抓取、todo、goal、skill、计划模式。
  /// dsh 只负责思考下一步并按 Remlark 的 JSON 协议回复，不调用任何自带工具（否则会浪费轮次，甚至搜索无关内容）
  static const disabledLocalTools = [
    'tool-bash',
    'tool-pwsh',
    'tool-jobs',
    'tool-fs',
    'tool-fs-search',
    'tool-workflow',
    'tool-subagent',
    'tool-subagent-fork',
    'tool-subagent-control',
    'tool-subagent-list-agents',
    'tool-working-directory',
    'tool-web',
    'tool-todo',
    'tool-goal',
    'tool-skill',
    'plan-mode',
  ];

  /// 创建 DSH_HOME 与工作目录（DSH_HOME 中可能保存凭据，仅当前用户可访问），写入补丁文件
  Future<void> prepare() async {
    final home = Directory(homeDir);
    if (!await home.exists()) {
      await home.create(recursive: true);
      await PlatformUtils.restrictDirectory(home.path);
    }
    await Directory(workspaceDir).create(recursive: true);
    final yaml = StringBuffer('# Remlark 生成：关闭 dsh 的本机工具，每次启动覆盖\n');
    for (final id in disabledLocalTools) {
      yaml.write('- id: $id\n  disabled: true\n');
    }
    await File(patchFile).writeAsString(yaml.toString());
  }

  static Future<DshEnvironment>? _current;

  /// 测试时替换为临时目录
  @visibleForTesting
  static set override(DshEnvironment? env) => _current = env == null ? null : Future.value(env);

  /// 当前应用使用的目录布局（首次调用时解析应用数据目录，之后复用）
  static Future<DshEnvironment> current() {
    return _current ??= () async {
      final data = await PlatformUtils.dataDir();
      return DshEnvironment(p.join(data.path, 'dsh'), DshPlatform.current());
    }();
  }
}
