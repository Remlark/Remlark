import 'dart:async';
import 'dart:io';

import '../../../l10n/app_localizations.dart';
import '../../../utils/app_version.dart';
import '../runtime/json_rpc_connection.dart';
import '../runtime/agent_options.dart';
import 'dsh_config_options.dart';
import 'dsh_environment.dart';
import 'dsh_types.dart';

/// 启动一个已完成 ACP 握手前的连接（测试时替换为内存中的假 Agent）
typedef AcpLauncher = Future<JsonRpcConnection> Function(String? apiKey);

/// 一个 dsh 子进程及其上的会话
class DshPeer {
  DshPeer(this.connection) {
    connection.notifications.listen((n) {
      if (n.method != 'session/update') return;
      final sid = n.params['sessionId'];
      final update = n.params['update'];
      if (sid is String && update is Map<String, dynamic>) _listeners[sid]?.call(update);
    });
    connection.onRequest = _onRequest;
  }

  final JsonRpcConnection connection;

  /// 本进程中已创建或恢复的会话（可以直接提问）
  final Set<String> liveSessions = {};

  /// 各会话当前的配置项（模型、推理强度），创建、恢复与修改配置时更新
  final Map<String, Object?> sessionConfig = {};

  /// 各配置项的默认值（本进程第一次看到该配置项时的当前值）：配置为“默认”时切回它
  final Map<String, String> configDefaults = {};

  /// 记录会话 [sessionId] 的配置项
  void recordConfig(String sessionId, Object? configOptions) {
    if (configOptions is! List) return;
    sessionConfig[sessionId] = configOptions;
    for (final o in configOptions.whereType<Map>()) {
      final id = o['id'];
      final current = o['currentValue'];
      if (id is String && current != null) configDefaults.putIfAbsent(id, () => '$current');
    }
  }

  final _listeners = <String, void Function(Map<String, dynamic> update)>{};

  /// 订阅会话 [sessionId] 的更新（同一会话同时只有一个提示词，后订阅者覆盖前者）
  void listen(String sessionId, void Function(Map<String, dynamic> update) onUpdate) =>
      _listeners[sessionId] = onUpdate;

  /// 取消订阅
  void unlisten(String sessionId) => _listeners.remove(sessionId);

  /// 对端请求：权限确认一律拒绝（终端助手只回答问题，不在本机执行工具），其他请求不支持
  Future<Map<String, dynamic>> _onRequest(String method, Map<String, dynamic> params) async {
    if (method != 'session/request_permission') throw JsonRpcException('unsupported: $method', code: -32601);
    final options = (params['options'] as List?)?.whereType<Map>() ?? const <Map>[];
    for (final kind in const ['reject_once', 'reject_always']) {
      for (final o in options) {
        if (o['kind'] == kind) {
          return {
            'outcome': {'outcome': 'selected', 'optionId': o['optionId']},
          };
        }
      }
    }
    return {
      'outcome': {'outcome': 'cancelled'},
    };
  }
}

/// dsh ACP 服务：以 `dsh --profile acp` 常驻子进程的方式运行 dsh，所有聊天共用。
///
/// 每个 API Key 一个进程（Key 以环境变量传入，不同 Key 不能共用进程）；首次提问时启动，
/// 进程退出后下次提问自动重启；安装或升级 dsh 前调用 [shutdown] 结束所有进程。
class DshAcpService {
  DshAcpService({AcpLauncher? launcher, Future<String> Function()? workspace})
    : _launcher = launcher ?? launchLocal,
      _workspace = workspace ?? (() async => (await DshEnvironment.current()).workspaceDir);

  /// 全局实例（AgentFactory 创建的 Agent 通过它获取进程）
  static DshAcpService shared = DshAcpService();

  final AcpLauncher _launcher;
  final Future<String> Function() _workspace;
  final _peers = <String, Future<DshPeer>>{};

  /// 各 API Key 可选的模型与推理强度（新建一个会话读取其配置项，进程退出前缓存）
  final _options = <String, Future<AgentOptions>>{};

  /// ACP 协议版本
  static const protocolVersion = 1;

  /// 启动握手超时（首次启动需要初始化 profile）
  static const initializeTimeout = Duration(seconds: 90);

  /// 会话的工作目录（绝对路径，空目录）
  Future<String> workspaceDir() => _workspace();

  /// 获取（必要时启动）[apiKey] 对应的进程
  Future<DshPeer> peer(String? apiKey) {
    final key = apiKey ?? '';
    final existing = _peers[key];
    if (existing != null) return existing;
    final future = _start(apiKey);
    _peers[key] = future;
    // 启动失败或进程退出后移除，下次重新启动
    future.then(
      (p) => p.connection.done.then((_) {
        if (identical(_peers[key], future)) _peers.remove(key);
      }),
      onError: (_) {
        if (identical(_peers[key], future)) _peers.remove(key);
      },
    );
    return future;
  }

  /// 启动进程并完成 ACP 握手
  Future<DshPeer> _start(String? apiKey) async {
    final conn = await _launcher(apiKey);
    try {
      final r = await conn.call('initialize', {
        'protocolVersion': protocolVersion,
        'clientCapabilities': {
          'fs': {'readTextFile': false, 'writeTextFile': false},
          'terminal': false,
        },
        'clientInfo': {'name': 'remlark', 'title': 'Remlark', 'version': appVersion},
      }, timeout: initializeTimeout);
      final v = r['protocolVersion'];
      if (v is num && v.toInt() != protocolVersion) throw JsonRpcException('ACP protocol $v');
    } catch (e) {
      await conn.close();
      throw DshException(S.current.t('dsh.err.start', {'error': '$e'}));
    }
    return DshPeer(conn);
  }

  /// 读取 [apiKey] 对应进程可选的模型与推理强度；[force] 时重新读取
  Future<AgentOptions> options(String? apiKey, {bool force = false}) {
    final key = apiKey ?? '';
    final cached = _options[key];
    if (!force && cached != null) return cached;
    final future = () async {
      final p = await peer(apiKey);
      final r = await p.connection.call('session/new', {
        'cwd': await workspaceDir(),
        'mcpServers': const [],
      }, timeout: const Duration(seconds: 60));
      return DshConfigOptions.toAgentOptions(r['configOptions']);
    }();
    _options[key] = future;
    // 失败时不缓存，下次重试
    future.catchError((Object _) {
      if (identical(_options[key], future)) _options.remove(key);
      return const AgentOptions([]);
    });
    return future;
  }

  /// 结束所有 dsh 进程
  Future<void> shutdown() async {
    _options.clear();
    final peers = _peers.values.toList();
    _peers.clear();
    for (final f in peers) {
      try {
        await (await f).connection.close();
      } catch (_) {
        // 启动失败的进程无需关闭
      }
    }
  }

  /// 启动本地安装的 dsh：私有 node 运行入口脚本，工作目录为空目录，附加关闭本机工具的补丁
  /// [extraEnvironment] 追加到子进程环境（测试时指定假的模型服务地址）
  static Future<JsonRpcConnection> launchLocal(String? apiKey, {Map<String, String> extraEnvironment = const {}}) async {
    final env = await DshEnvironment.current();
    if (!env.installed) throw DshException(S.current.t('dsh.err.not_installed'));
    await env.prepare();
    final Process process;
    try {
      process = await Process.start(
        env.nodeExecutable,
        [env.dshEntry(), '--profile', 'acp', '--patch', env.patchFile],
        environment: {...env.processEnvironment(apiKey: apiKey), ...extraEnvironment},
        workingDirectory: env.workspaceDir,
      );
    } on ProcessException catch (e) {
      throw DshException(S.current.t('dsh.err.start', {'error': e.message}));
    }
    return JsonRpcConnection(
      process.stdout,
      process.stdin,
      stderr: process.stderr,
      onClose: () async {
        // 关闭 stdin 后 dsh 会自行停止会话并退出；超时再强制结束
        final code = await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
        if (code == -1) {
          process.kill();
          await process.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          });
        }
      },
    );
  }
}
