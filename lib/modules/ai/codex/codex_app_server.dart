import 'dart:async';
import 'dart:io';

import '../../../l10n/app_localizations.dart';
import '../../../utils/app_version.dart';
import '../runtime/json_rpc_connection.dart';
import 'codex_environment.dart';
import 'codex_types.dart';

/// 启动一个尚未完成握手的 app-server 连接（测试时替换为内存中的假 app-server）
typedef CodexLauncher = Future<JsonRpcConnection> Function(String homeId);

/// 一个常驻的 app-server 子进程及其上的线程
class CodexPeer {
  CodexPeer(this.connection) {
    connection.notifications.listen((n) {
      final tid = n.params['threadId'];
      if (tid is String) _listeners[tid]?.call(n);
    });
    // 审批、提问等请求一律不支持：线程设置为从不请求审批，Codex 也没有可在本机执行的工具
    connection.onRequest = (method, _) async => throw JsonRpcException('unsupported: $method', code: -32601);
  }

  final JsonRpcConnection connection;

  /// 本进程中已创建或恢复的线程（可以直接开始新一轮）
  final Set<String> liveThreads = {};

  final _listeners = <String, void Function(JsonRpcNotification n)>{};

  /// 订阅线程 [threadId] 的通知（同一线程同时只有一轮对话，后订阅者覆盖前者）
  void listen(String threadId, void Function(JsonRpcNotification n) onNotification) =>
      _listeners[threadId] = onNotification;

  /// 取消订阅
  void unlisten(String threadId) => _listeners.remove(threadId);
}

/// Codex app-server 服务：以 `codex app-server` 子进程运行 Codex（标准输入输出上的 JSON-RPC）。
///
/// 聊天使用常驻进程（每个 Agent 的 CODEX_HOME 一个，首次提问时启动，退出后下次提问自动重启）；
/// 设置页读取账号、模型与登录使用短生命周期进程（[open]），用完即关闭。
/// 登录或退出后调用 [restart] 让常驻进程重新读取凭据；安装或升级前调用 [shutdown] 结束所有进程。
class CodexAppServer {
  CodexAppServer({CodexLauncher? launcher, Future<String> Function()? workspace})
    : _launcher = launcher ?? launchLocal,
      _workspace = workspace ?? (() async => (await CodexEnvironment.current()).workspaceDir);

  /// 全局实例（AgentFactory 创建的 Agent 与设置页通过它获取进程）
  static CodexAppServer shared = CodexAppServer();

  final CodexLauncher _launcher;
  final Future<String> Function() _workspace;
  final _peers = <String, Future<CodexPeer>>{};

  /// 各 CODEX_HOME 最近一次启动（启动 + 握手）完成的时刻，用于排队
  final _starting = <String, Future<void>>{};

  /// 握手超时（首次启动需要初始化 CODEX_HOME）
  static const initializeTimeout = Duration(seconds: 60);

  /// 会话的工作目录（绝对路径，空目录）
  Future<String> workspaceDir() => _workspace();

  /// 获取（必要时启动）Agent [homeId] 的常驻进程
  Future<CodexPeer> peer(String homeId) {
    final existing = _peers[homeId];
    if (existing != null) return existing;
    final future = open(homeId).then(CodexPeer.new);
    _peers[homeId] = future;
    // 启动失败或进程退出后移除，下次重新启动
    future.then(
      (p) => p.connection.done.then((_) {
        if (identical(_peers[homeId], future)) _peers.remove(homeId);
      }),
      onError: (_) {
        if (identical(_peers[homeId], future)) _peers.remove(homeId);
      },
    );
    return future;
  }

  /// 启动一个新进程并完成握手；调用方负责关闭。
  ///
  /// 同一 CODEX_HOME 的启动排队进行：多个进程同时初始化 CODEX_HOME 中的 sqlite 状态库会失败
  /// （"failed to initialize sqlite state runtime"，新目录上很容易出现，如编辑框同时读取账号与模型）。
  /// 前一个进程握手完成后再启动下一个；启动完成后多个进程可以同时运行
  Future<JsonRpcConnection> open(String homeId) async {
    final previous = _starting[homeId];
    final done = Completer<void>();
    _starting[homeId] = done.future;
    try {
      if (previous != null) await previous;
      return await _openNow(homeId);
    } finally {
      done.complete();
      if (identical(_starting[homeId], done.future)) _starting.remove(homeId);
    }
  }

  /// 立即启动进程并握手
  Future<JsonRpcConnection> _openNow(String homeId) async {
    final conn = await _launcher(homeId);
    try {
      await conn.call('initialize', {
        'clientInfo': {'name': 'remlark', 'title': 'Remlark', 'version': appVersion},
      }, timeout: initializeTimeout);
      conn.notify('initialized', const {});
    } catch (e) {
      await conn.close();
      throw CodexException(S.current.t('codex.err.start', {'error': '$e'}));
    }
    return conn;
  }

  /// 结束 Agent [homeId] 的常驻进程（登录状态变化后，下次提问用新凭据重新启动）
  Future<void> restart(String homeId) async {
    final f = _peers.remove(homeId);
    if (f == null) return;
    try {
      await (await f).connection.close();
    } catch (_) {
      // 启动失败的进程无需关闭
    }
  }

  /// 结束所有常驻进程
  Future<void> shutdown() async {
    for (final id in _peers.keys.toList()) {
      await restart(id);
    }
  }

  /// 启动本地安装的 Codex：指定该 Agent 的 CODEX_HOME，工作目录为空目录，关闭本机工具
  static Future<JsonRpcConnection> launchLocal(String homeId) async {
    final env = await CodexEnvironment.current();
    if (!env.installed) throw CodexException(S.current.t('codex.err.not_installed'));
    await env.prepare(homeId);
    final Process process;
    try {
      process = await Process.start(
        env.executable,
        CodexEnvironment.appServerArgs,
        environment: env.processEnvironment(homeId),
        workingDirectory: env.workspaceDir,
      );
    } on ProcessException catch (e) {
      throw CodexException(S.current.t('codex.err.start', {'error': e.message}));
    }
    return JsonRpcConnection(
      process.stdout,
      process.stdin,
      stderr: process.stderr,
      onClose: () async {
        // 关闭 stdin 后 app-server 会自行退出；超时再强制结束
        final code = await process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
        if (code == -1) {
          process.kill();
          await process.exitCode.timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
        }
      },
    );
  }
}
