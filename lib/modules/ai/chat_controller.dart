import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/database.dart';
import 'agent_config.dart';
import 'agent_factory.dart';
import 'agent_interface.dart';
import 'chat_repository.dart';
import 'token_repository.dart';

/// 界面上的一条聊天消息
class UiChatMessage {
  UiChatMessage(this.role, this.content, {this.reasoning = ''});

  final String role;
  String content;
  String reasoning;
  int inputTokens = 0;
  int outputTokens = 0;
}

/// 本轮请求的实时统计（状态栏显示）
class ChatStats {
  /// 输出速度 token/s（去掉首字前的等待时间）
  double tokensPerSecond = 0;
  int inputTokens = 0;
  int outputTokens = 0;
  int contextTokens = 0;

  /// 首字延迟（毫秒）
  int? firstTokenMs;
  bool estimated = false;
}

/// 聊天控制器：每个终端会话一个，负责与 Agent 交互、持久化记录与 token 统计
class ChatController extends ChangeNotifier {
  ChatController({required this.chats, required this.tokens, this.hostName = ''});

  final ChatRepository chats;
  final TokenRepository tokens;
  final String hostName;

  final List<UiChatMessage> messages = [];
  final ChatStats stats = ChatStats();
  ChatSession? _session;
  AiAgent? _agent;
  bool busy = false;
  StreamSubscription<AgentEvent>? _sub;

  /// 当前会话（未发送消息时为空）
  ChatSession? get session => _session;

  /// 新建对话
  void newChat() {
    stop();
    _session = null;
    messages.clear();
    _resetStats();
    notifyListeners();
  }

  void _resetStats() {
    stats
      ..tokensPerSecond = 0
      ..inputTokens = 0
      ..outputTokens = 0
      ..contextTokens = 0
      ..firstTokenMs = null
      ..estimated = false;
  }

  /// 载入历史会话继续聊天
  Future<void> loadSession(ChatSession s) async {
    stop();
    _session = s;
    messages
      ..clear()
      ..addAll(
        (await chats.messages(s.id)).map(
          (m) => UiChatMessage(m.role, m.content)
            ..inputTokens = m.inputTokens
            ..outputTokens = m.outputTokens,
        ),
      );
    _resetStats();
    notifyListeners();
  }

  /// 发送消息。[context] 为附加的终端上下文（选中内容或最近输出）
  Future<void> send(AgentSettings agentSettings, String prompt, {String? context}) async {
    if (busy || prompt.trim().isEmpty) return;
    final fullPrompt = context == null || context.isEmpty ? prompt : '$prompt\n\n```terminal\n$context\n```';
    final agent = AgentFactory.create(agentSettings);
    _agent = agent;
    final history = messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => AgentMessage(m.role, m.content))
        .toList();

    _session ??= await chats.createSession(
      title: prompt.length > 40 ? '${prompt.substring(0, 40)}…' : prompt,
      agentUuid: agentSettings.uuid,
      agentName: agentSettings.name,
      model: agent.model,
      hostName: hostName,
    );
    final sessionId = _session!.id;
    messages.add(UiChatMessage('user', fullPrompt));
    await chats.addMessage(sessionId, 'user', fullPrompt);
    final reply = UiChatMessage('assistant', '');
    messages.add(reply);
    busy = true;
    _resetStats();
    notifyListeners();

    final start = DateTime.now();
    DateTime? firstToken;
    var liveOut = 0;
    AgentUsage? usage;
    String? externalId;
    final done = Completer<void>();
    final roundErrors = <String>[];

    void updateSpeed() {
      if (firstToken == null) return;
      final ms = DateTime.now().difference(firstToken!).inMilliseconds;
      final out = usage?.outputTokens ?? liveOut;
      stats.tokensPerSecond = ms > 0 ? out * 1000 / ms : 0;
    }

    _sub = agent
        .send(
          AgentRequest(
            history: _session!.externalSessionId != null && agentSettings.kind == AgentKind.deepseekCli
                ? const []
                : history,
            prompt: fullPrompt,
            externalSessionId: agentSettings.kind == AgentKind.deepseekCli ? _session!.externalSessionId : null,
            systemPrompt: agentSettings.systemPrompt.isNotEmpty ? agentSettings.systemPrompt : _defaultSystemPrompt,
          ),
        )
        .listen(
          (e) {
            switch (e) {
              case AgentTextDelta(:final text):
                firstToken ??= DateTime.now();
                stats.firstTokenMs ??= firstToken!.difference(start).inMilliseconds;
                reply.content += text;
                liveOut += estimateTokens(text);
                stats.outputTokens = liveOut;
                updateSpeed();
              case AgentReasoningDelta(:final text):
                firstToken ??= DateTime.now();
                stats.firstTokenMs ??= firstToken!.difference(start).inMilliseconds;
                reply.reasoning += text;
                liveOut += estimateTokens(text);
                updateSpeed();
              case AgentUsage():
                usage = e;
                stats
                  ..inputTokens = e.inputTokens
                  ..outputTokens = e.outputTokens
                  ..contextTokens = e.contextTokens ?? e.inputTokens + e.outputTokens
                  ..estimated = e.estimated;
                updateSpeed();
              case AgentSessionId(:final id):
                externalId = id;
              case AgentError(:final message):
                roundErrors.add(message);
                messages.add(UiChatMessage('error', message));
            }
            notifyListeners();
          },
          onDone: () => done.complete(),
          onError: (Object e) {
            roundErrors.add('$e');
            messages.add(UiChatMessage('error', '$e'));
            done.complete();
          },
        );

    await done.future;
    _sub = null;
    _agent = null;
    busy = false;
    final u = usage;
    reply.inputTokens = u?.inputTokens ?? 0;
    reply.outputTokens = u?.outputTokens ?? liveOut;
    if (reply.content.isNotEmpty) {
      await chats.addMessage(
        sessionId,
        'assistant',
        reply.content,
        inputTokens: reply.inputTokens,
        outputTokens: reply.outputTokens,
      );
    } else {
      messages.remove(reply);
    }
    for (final err in roundErrors) {
      await chats.addMessage(sessionId, 'error', err);
    }
    await chats.touchSession(sessionId, externalSessionId: externalId);
    if (externalId != null) _session = await chats.getSession(sessionId);
    if (u != null || liveOut > 0) {
      await tokens.record(
        agentUuid: agentSettings.uuid,
        agentName: agentSettings.name,
        model: agent.model,
        input: u?.inputTokens ?? 0,
        output: u?.outputTokens ?? liveOut,
      );
    }
    notifyListeners();
  }

  /// 停止当前回答
  void stop() {
    _agent?.cancel();
  }

  static const _defaultSystemPrompt =
      'You are an assistant embedded in an SSH terminal client. '
      'When suggesting shell commands, put each runnable command in its own ```bash code block. '
      'Be concise.';

  @override
  void dispose() {
    stop();
    _sub?.cancel();
    super.dispose();
  }
}
