import 'dart:async';

import '../../../l10n/app_localizations.dart';
import '../agent_config.dart';
import '../agent_interface.dart';
import '../codex/codex_account_service.dart';
import '../codex/codex_app_server.dart';
import '../codex/codex_types.dart';
import '../runtime/json_rpc_connection.dart';

/// Codex Agent：通过 [CodexAppServer] 的常驻 app-server 子进程提问，每个 Agent 使用自己的 CODEX_HOME（登录账号）。
///
/// 每个聊天对应一个 Codex 线程：首次提问 `thread/start`，之后在同一进程中直接 `turn/start` 续问；
/// 进程重启后用 `thread/resume` 恢复（Codex 自己保存上下文）；恢复失败时新建线程并附上之前的对话。
/// 系统提示词（终端操作协议）作为线程的 baseInstructions，替换 Codex 默认的编程助手提示词；
/// 线程只读、从不请求审批、工作目录为空目录，本机工具已在启动参数中关闭。
class CodexAgent implements AiAgent {
  CodexAgent(this.settings, {CodexAppServer? server}) : _server = server ?? CodexAppServer.shared;

  final AgentSettings settings;
  final CodexAppServer _server;

  /// 当前提问的进程、线程与轮次（取消时使用）
  CodexPeer? _peer;
  String? _threadId;
  String? _turnId;
  Completer<Map?>? _turnDone;
  bool _cancelled = false;

  @override
  String get name => settings.name;

  @override
  String get model => settings.model.isEmpty ? 'codex' : settings.model;

  @override
  Stream<AgentEvent> send(AgentRequest request) {
    final controller = StreamController<AgentEvent>();
    _cancelled = false;
    unawaited(_run(request, controller));
    return controller.stream;
  }

  /// 完成一轮提问，事件写入 [out]，结束时关闭
  Future<void> _run(AgentRequest request, StreamController<AgentEvent> out) async {
    final output = StringBuffer();
    var promptText = request.prompt;
    var input = 0;
    var outputTokens = 0;
    int? contextTokens;
    var reported = false;
    try {
      final peer = await _server.peer(settings.uuid);
      _peer = peer;
      // 未登录时对话会反复重试后才失败，先检查以便立即给出明确提示
      if (await CodexAccountService.readAccountWith(peer.connection) == null) {
        throw CodexException(S.current.t('codex.err.login_required'));
      }
      final (threadId, fresh) = await _openThread(peer, request);
      _threadId = threadId;
      if (threadId != request.externalSessionId) out.add(AgentSessionId(threadId));
      if (fresh) promptText = _firstPrompt(request);
      if (_cancelled) return;

      final done = _turnDone = Completer<Map?>();
      final streamed = <String>{};
      String? lastError;
      peer.listen(threadId, (n) {
        final p = n.params;
        switch (n.method) {
          case 'item/agentMessage/delta':
            final d = p['delta'];
            if (d is String && d.isNotEmpty) {
              streamed.add('${p['itemId']}');
              output.write(d);
              out.add(AgentTextDelta(d));
            }
          case 'item/reasoning/summaryTextDelta':
            final d = p['delta'];
            if (d is String && d.isNotEmpty) out.add(AgentReasoningDelta(d));
          case 'item/completed':
            // 没有收到增量时（部分版本或模型）使用完整消息
            final item = p['item'];
            if (item is Map && item['type'] == 'agentMessage' && !streamed.contains('${item['id']}')) {
              final t = '${item['text'] ?? ''}';
              if (t.isNotEmpty) {
                output.write(t);
                out.add(AgentTextDelta(t));
              }
            }
          case 'thread/tokenUsage/updated':
            // last 为最近一次模型调用的用量：一轮中可能多次调用，输入输出累加，上下文取最近一次
            final usage = p['tokenUsage'];
            final last = usage is Map ? usage['last'] : null;
            if (last is Map) {
              reported = true;
              input += (last['inputTokens'] as num?)?.toInt() ?? 0;
              outputTokens += (last['outputTokens'] as num?)?.toInt() ?? 0;
              contextTokens = (last['totalTokens'] as num?)?.toInt();
            }
          case 'error':
            final e = p['error'];
            if (p['willRetry'] != true) lastError = e is Map ? '${e['message'] ?? e}' : '$e';
          case 'turn/completed':
            if (!done.isCompleted) done.complete(p['turn'] is Map ? p['turn'] as Map : const {});
        }
      });
      // 进程意外退出时结束等待
      unawaited(
        peer.connection.done.then((_) {
          if (!done.isCompleted) done.completeError(CodexException(peer.connection.closeReason ?? 'closed'));
        }),
      );
      final r = await peer.connection.call('turn/start', {
        'threadId': threadId,
        'input': [
          {'type': 'text', 'text': promptText},
        ],
        // 模型与推理强度按轮设置：聊天中途切换也立即生效
        if (settings.model.isNotEmpty) 'model': settings.model,
        if (settings.reasoningEffort.isNotEmpty) 'effort': settings.reasoningEffort,
      }, timeout: const Duration(seconds: 60));
      final turn = r['turn'];
      _turnId = turn is Map ? turn['id']?.toString() : null;
      if (_cancelled) await _interrupt();
      final result = await done.future;
      final status = result?['status'];
      if (status != 'completed' && !_cancelled) {
        final err = result?['error'];
        out.add(
          AgentError(
            err is Map ? '${err['message'] ?? err}' : lastError ?? S.current.t('codex.err.turn', {'status': '$status'}),
          ),
        );
      }
    } on CodexException catch (e) {
      if (!_cancelled) out.add(AgentError(e.message));
    } on JsonRpcException catch (e) {
      if (!_cancelled) out.add(AgentError(e.message));
    } catch (e) {
      if (!_cancelled) out.add(AgentError('$e'));
    } finally {
      final tid = _threadId;
      if (tid != null) _peer?.unlisten(tid);
      _peer = null;
      _turnId = null;
      _turnDone = null;
      out.add(
        reported
            ? AgentUsage(inputTokens: input, outputTokens: outputTokens, contextTokens: contextTokens)
            : AgentUsage(
                inputTokens: estimateTokens(promptText),
                outputTokens: estimateTokens(output.toString()),
                estimated: true,
              ),
      );
      await out.close();
    }
  }

  /// 打开线程：进程中已有则直接使用，否则先尝试恢复，失败再新建。返回线程 id 与是否为新线程
  Future<(String, bool)> _openThread(CodexPeer peer, AgentRequest request) async {
    final externalId = request.externalSessionId;
    if (externalId != null && peer.liveThreads.contains(externalId)) return (externalId, false);
    final params = {
      'cwd': await _server.workspaceDir(),
      'sandbox': 'read-only',
      'approvalPolicy': 'never',
      if (request.systemPrompt.isNotEmpty) 'baseInstructions': request.systemPrompt,
      if (settings.model.isNotEmpty) 'model': settings.model,
    };
    if (externalId != null) {
      try {
        await peer.connection.call('thread/resume', {
          ...params,
          'threadId': externalId,
        }, timeout: const Duration(seconds: 60));
        peer.liveThreads.add(externalId);
        return (externalId, false);
      } on JsonRpcException catch (_) {
        // 线程不存在或已损坏：新建线程
      }
    }
    final r = await peer.connection.call('thread/start', params, timeout: const Duration(seconds: 60));
    final thread = r['thread'];
    final id = thread is Map ? thread['id'] : null;
    if (id is! String || id.isEmpty) throw CodexException('thread/start: id');
    peer.liveThreads.add(id);
    return (id, true);
  }

  /// 新线程的第一条消息：之前的对话（线程恢复失败时保留上下文）+ 本次问题；系统提示词已作为 baseInstructions
  static String _firstPrompt(AgentRequest r) {
    if (r.history.isEmpty) return r.prompt;
    final b = StringBuffer('Previous conversation:\n');
    for (final m in r.history) {
      b.writeln('${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}');
    }
    b
      ..writeln()
      ..write(r.prompt);
    return b.toString();
  }

  /// 中断当前轮次
  Future<void> _interrupt() async {
    final peer = _peer;
    final tid = _threadId;
    final turn = _turnId;
    if (peer == null || tid == null || turn == null) return;
    try {
      await peer.connection.call('turn/interrupt', {
        'threadId': tid,
        'turnId': turn,
      }, timeout: const Duration(seconds: 10));
    } catch (_) {
      // 中断失败时直接结束等待
    }
  }

  @override
  void cancel() {
    _cancelled = true;
    unawaited(_interrupt());
    final done = _turnDone;
    if (done != null && !done.isCompleted) done.complete(null);
  }
}
