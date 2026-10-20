import 'dart:async';

import '../../../l10n/app_localizations.dart';
import '../../../utils/app_log.dart';
import '../agent_config.dart';
import '../agent_interface.dart';
import '../runtime/json_rpc_connection.dart';
import '../dsh/dsh_acp_service.dart';
import '../dsh/dsh_config_options.dart';

/// DeepSeek Harness（dsh）Agent：通过 [DshAcpService] 的常驻 ACP 子进程提问。
///
/// 每个聊天对应一个 dsh 会话：首次提问 `session/new`，之后在同一进程中直接续问；
/// 进程重启后用 `session/resume` 恢复（dsh 自己保存上下文）；恢复失败时新建会话并附上之前的对话。
class DeepSeekHarnessAgent implements AiAgent {
  DeepSeekHarnessAgent(this.settings, {DshAcpService? service}) : _service = service ?? DshAcpService.shared;

  final AgentSettings settings;
  final DshAcpService _service;

  /// 当前提问的进程与会话（取消时使用）
  DshPeer? _peer;
  String? _sessionId;
  bool _cancelled = false;

  @override
  String get name => settings.name;

  @override
  String get model => settings.model.isEmpty ? 'deepseek-harness' : settings.model;

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
    int? contextUsed;
    try {
      final peer = await _service.peer(settings.apiKey);
      _peer = peer;
      final (sessionId, fresh) = await _openSession(peer, request.externalSessionId);
      _sessionId = sessionId;
      if (sessionId != request.externalSessionId) out.add(AgentSessionId(sessionId));
      if (fresh) promptText = _firstPrompt(request);
      // 每轮按 Agent 配置切换模型与推理强度：聊天中途切换也立即生效
      await _applyConfig(peer, sessionId);

      var lastUpdate = DateTime.now();
      var settled = false;
      peer.listen(sessionId, (u) {
        lastUpdate = DateTime.now();
        if (settled) AppLog.w('dsh', '提问结束后才收到更新：${u['sessionUpdate']}');
        switch (u['sessionUpdate']) {
          case 'agent_message_chunk':
            final t = _text(u['content']);
            if (t != null) {
              output.write(t);
              out.add(AgentTextDelta(t));
            }
          case 'agent_thought_chunk':
            final t = _text(u['content']);
            if (t != null) out.add(AgentReasoningDelta(t));
          case 'tool_call':
            final title = u['title'];
            if (title is String && title.isNotEmpty) {
              out.add(AgentReasoningDelta('\n${S.current.t('dsh.tool_call', {'title': title})}\n'));
            }
          case 'usage_update':
            final used = u['used'];
            if (used is num) contextUsed = used.toInt();
        }
      });
      if (_cancelled) return;
      final r = await peer.connection.call('session/prompt', {
        'sessionId': sessionId,
        'prompt': [
          {'type': 'text', 'text': promptText},
        ],
      });
      settled = true;
      if (r['stopReason'] != 'cancelled') await _drainLateUpdates(() => lastUpdate, () => output.isEmpty);
      final stop = r['stopReason'];
      if (stop == 'refusal' || stop == 'max_tokens') {
        out.add(AgentError(S.current.t('dsh.stop.$stop')));
      }
    } on JsonRpcException catch (e) {
      if (!_cancelled) out.add(AgentError(e.message));
    } catch (e) {
      if (!_cancelled) out.add(AgentError('$e'));
    } finally {
      final sid = _sessionId;
      if (sid != null) _peer?.unlisten(sid);
      _peer = null;
      // dsh 只报告上下文占用，输入输出按文本估算
      out.add(
        AgentUsage(
          inputTokens: estimateTokens(promptText),
          outputTokens: estimateTokens(output.toString()),
          contextTokens: contextUsed,
          estimated: true,
        ),
      );
      await out.close();
    }
  }

  /// 提问结束后的静默时间：期间没有新更新才结束本轮
  static Duration settleQuiet = const Duration(milliseconds: 300);

  /// 还没收到回答文本时最多再等多久
  static Duration settleEmptyMax = const Duration(seconds: 5);

  /// 提问结束后继续接收迟到的更新：dsh 偶尔在提问结束的响应之后才送达最后一条消息，
  /// 立即结束会丢掉回答。等到 [settleQuiet] 内没有新更新为止；还没有回答文本时最多等 [settleEmptyMax]
  Future<void> _drainLateUpdates(DateTime Function() lastUpdate, bool Function() noText) async {
    final start = DateTime.now();
    while (!_cancelled) {
      final now = DateTime.now();
      final quiet = now.difference(lastUpdate()) >= settleQuiet && now.difference(start) >= settleQuiet;
      if (quiet && (!noText() || now.difference(start) >= settleEmptyMax)) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  /// 打开会话：进程中已有则直接使用，否则先尝试恢复，失败再新建。返回会话 id 与是否为新会话
  Future<(String, bool)> _openSession(DshPeer peer, String? externalId) async {
    final live = peer.liveSessions;
    if (externalId != null && live.contains(externalId)) return (externalId, false);
    final cwd = await _service.workspaceDir();
    if (externalId != null) {
      try {
        final r = await peer.connection.call('session/resume', {
          'sessionId': externalId,
          'cwd': cwd,
          'mcpServers': const [],
        }, timeout: const Duration(seconds: 60));
        live.add(externalId);
        peer.recordConfig(externalId, r['configOptions']);
        return (externalId, false);
      } on JsonRpcException catch (_) {
        // 会话不存在或已损坏：新建会话
      }
    }
    final r = await peer.connection.call('session/new', {
      'cwd': cwd,
      'mcpServers': const [],
    }, timeout: const Duration(seconds: 60));
    final id = r['sessionId'];
    if (id is! String || id.isEmpty) throw JsonRpcException('session/new: sessionId');
    live.add(id);
    peer.recordConfig(id, r['configOptions']);
    return (id, true);
  }

  /// 按 Agent 配置切换会话的模型与推理强度：按名称或值匹配会话公布的选项，找不到则不切换；
  /// 配置为“默认”（空）时切回该配置项的默认值
  Future<void> _applyConfig(DshPeer peer, String sessionId) async {
    final wanted = <Map? Function(Object?), String>{
      DshConfigOptions.model: settings.model.trim(),
      DshConfigOptions.effort: settings.reasoningEffort,
    };
    for (final MapEntry(key: find, value: want) in wanted.entries) {
      final opt = find(peer.sessionConfig[sessionId]);
      if (opt == null) continue;
      final value = want.isEmpty ? peer.configDefaults[opt['id']] : DshConfigOptions.valueOf(opt, want);
      if (value == null || value == '${opt['currentValue']}') continue;
      final r = await peer.connection.call('session/set_config_option', {
        'sessionId': sessionId,
        'configId': opt['id'],
        'value': value,
      }, timeout: const Duration(seconds: 30));
      if (r['configOptions'] is List) {
        peer.recordConfig(sessionId, r['configOptions']);
      } else {
        opt['currentValue'] = value;
      }
    }
  }

  /// 新会话的第一条消息：系统提示词 + 之前的对话（会话恢复失败时保留上下文）+ 本次问题
  static String _firstPrompt(AgentRequest r) {
    final b = StringBuffer();
    if (r.systemPrompt.isNotEmpty) b.writeln('${r.systemPrompt}\n');
    if (r.history.isNotEmpty) {
      b.writeln('Previous conversation:');
      for (final m in r.history) {
        b.writeln('${m.role == 'user' ? 'User' : 'Assistant'}: ${m.content}');
      }
      b.writeln();
    }
    b.write(r.prompt);
    return b.toString();
  }

  /// 取出内容块中的文本（图片等非文本块忽略）
  static String? _text(Object? content) {
    if (content is Map && content['type'] == 'text' && content['text'] is String) {
      final t = content['text'] as String;
      return t.isEmpty ? null : t;
    }
    if (content is List) {
      final t = content.map(_text).whereType<String>().join();
      return t.isEmpty ? null : t;
    }
    return null;
  }

  @override
  void cancel() {
    _cancelled = true;
    final sid = _sessionId;
    final peer = _peer;
    if (sid != null && peer != null) peer.connection.notify('session/cancel', {'sessionId': sid});
  }
}
