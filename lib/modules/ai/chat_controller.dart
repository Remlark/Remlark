import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/database.dart';
import '../../l10n/app_localizations.dart';
import 'agent_config.dart';
import 'agent_factory.dart';
import 'agent_interface.dart';
import 'chat_repository.dart';
import 'terminal_agent/command_permission.dart';
import 'terminal_agent/terminal_agent_protocol.dart';
import 'terminal_agent/terminal_driver.dart';
import 'terminal_agent/terminal_step_runner.dart';
import 'token_repository.dart';

/// 界面上的一条聊天消息。role：user / assistant / terminal（交给 AI 的终端输出）/ error
class UiChatMessage {
  UiChatMessage(this.role, this.content, {this.reasoning = ''});

  final String role;
  String content;
  String reasoning;

  /// Agent 的原始回复（终端模式下为 JSON 动作；作为历史交给 Agent 时使用，界面显示整理后的 [content]）
  String? raw;
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

/// 聊天控制器：每个终端会话一个（切换标签页回来仍是同一个对话），负责与 Agent 交互、
/// 持久化记录与 token 统计。
///
/// 提供 [terminal] 且权限不是“只给建议”时，AI 通过 JSON 协议操作该终端：每轮回复一个动作（执行命令 / 等待 / 回答），
/// 执行后把终端新增输出作为下一轮提问发回，直到 AI 在聊天中给出回答。每一步都是一次独立提问，命令执行多久都可以。
class ChatController extends ChangeNotifier {
  ChatController({required this.chats, required this.tokens, this.hostName = '', this.terminal});

  final ChatRepository chats;
  final TokenRepository tokens;
  final String hostName;

  /// 本聊天所在的终端（null 时只能普通对话）
  final TerminalDriver? terminal;

  /// AI 执行命令的权限（每个终端标签页独立，新标签默认逐条确认）
  CommandPermission get permission => _permission;
  CommandPermission _permission = CommandPermission.ask;
  set permission(CommandPermission p) {
    if (p == _permission) return;
    _permission = p;
    notifyListeners();
  }

  /// 命令已填入终端，正在等待用户按回车
  bool waitingForEnter = false;

  final List<UiChatMessage> messages = [];
  final ChatStats stats = ChatStats();
  ChatSession? _session;
  AiAgent? _agent;
  StopSignal? _stop;
  bool busy = false;

  /// 上一轮是否为终端操作模式（中途切换时在本轮提问前告知 AI）
  bool? _lastOperated;

  /// 在本终端中新建的 dsh 会话 id（载入其他服务器的历史记录后，续问使用它而不是原记录的会话）
  String? _hereExternalId;

  /// 一次任务最多的步数（防止 AI 无限循环）
  static const maxSteps = 200;

  /// 当前会话（未发送消息时为空）
  ChatSession? get session => _session;

  /// 新建对话
  void newChat() {
    stop();
    _session = null;
    _hereExternalId = null;
    _lastOperated = null;
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
    _hereExternalId = null;
    _lastOperated = null;
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
    final before = _history();
    _session ??= await chats.createSession(
      title: prompt.length > 40 ? '${prompt.substring(0, 40)}…' : prompt,
      agentUuid: agentSettings.uuid,
      agentName: agentSettings.name,
      model: agent.model,
      hostName: hostName,
    );
    messages.add(UiChatMessage('user', fullPrompt));
    await chats.addMessage(_session!.id, 'user', fullPrompt);
    final stop = _stop = StopSignal();
    busy = true;
    notifyListeners();

    final term = terminal;
    final operate = term != null && _permission.operatesTerminal;
    final custom = agentSettings.systemPrompt.trim();
    final String systemPrompt;
    if (operate) {
      final protocol = TerminalAgentProtocol.systemPrompt(hostName);
      systemPrompt = custom.isEmpty ? protocol : '$protocol\n\nAdditional instructions from the user:\n$custom';
    } else {
      systemPrompt = custom.isEmpty ? _defaultSystemPrompt : custom;
    }
    var request = operate ? TerminalAgentProtocol.userPrompt(fullPrompt, term.screenText()) : fullPrompt;
    // 续聊中途切换了是否操作终端：系统提示词只在新会话时发送，因此在本轮提问前附上说明（不显示在界面）
    if (_lastOperated != null && _lastOperated != operate && _session!.externalSessionId != null) {
      request = operate
          ? '[From now on you operate the terminal. Follow these rules:\n$systemPrompt]\n\n$request'
          : '[The user turned off terminal control. Do not reply with JSON actions; answer normally and put '
                'runnable commands in ```bash code blocks for the user to run.]\n\n$request';
    }
    _lastOperated = operate;

    final runner = operate ? TerminalStepRunner(term, stop) : null;
    var history = before;
    var emptyRetries = 0;
    try {
      for (var step = 0; step < maxSteps && !stop.stopped; step++) {
        final text = await _turn(agentSettings, agent, request, systemPrompt, history, display: !operate);
        if (text == null || runner == null || stop.stopped) break;
        // 没有收到回复：请 AI 重新回复一次，仍然没有则提示用户（不能悄悄结束）
        if (text.trim().isEmpty) {
          if (emptyRetries++ < 1) {
            request = TerminalAgentProtocol.noReply;
            continue;
          }
          await _addMessage('error', S.current.t('ai.terminal.no_reply'));
          break;
        }
        emptyRetries = 0;
        final action = TerminalAgentProtocol.parse(text);
        await _showAction(action, text);
        // 下一步的历史：到本步回复为止的全部对话（dsh 自己保存上下文，不使用；无会话的 Agent 靠它保持整个任务的上下文）
        history = _history();
        String? output;
        switch (action.type) {
          case TerminalActionType.answer:
            return;
          case TerminalActionType.run:
            if (!term!.connected) {
              await _addMessage('error', S.current.t('ai.terminal.disconnected'));
              return;
            }
            output = await runner.run(
              action.command,
              autoSubmit: _permission.autoSubmits(action.command),
              onWaitingEnter: (w) {
                waitingForEnter = w;
                notifyListeners();
              },
            );
          case TerminalActionType.wait:
            output = await runner.wait(action.seconds);
        }
        if (stop.stopped) break;
        if (output == null) {
          request = TerminalAgentProtocol.notExecuted;
          continue;
        }
        await _addMessage('terminal', output);
        request = TerminalAgentProtocol.observation(output, afterWait: action.type == TerminalActionType.wait);
        if (step == maxSteps - 1) await _addMessage('error', S.current.t('ai.terminal.too_many_steps', {'n': maxSteps}));
      }
    } finally {
      await runner?.dispose();
      waitingForEnter = false;
      _agent = null;
      _stop = null;
      busy = false;
      notifyListeners();
    }
  }

  /// 提问一轮：流式显示（[display] 为 false 时只显示推理过程，回答文本由 [_showAction] 整理后显示），
  /// 记录统计与错误。返回 Agent 的完整回复文本（没有收到文本时为空字符串）；出错时返回 null
  Future<String?> _turn(
    AgentSettings settings,
    AiAgent agent,
    String prompt,
    String systemPrompt,
    List<AgentMessage> history, {
    required bool display,
  }) async {
    final sessionId = _session!.id;
    final reply = UiChatMessage('assistant', '');
    messages.add(reply);
    _resetStats();
    notifyListeners();

    final start = DateTime.now();
    final text = StringBuffer();
    DateTime? firstToken;
    var liveOut = 0;
    AgentUsage? usage;
    String? externalId;
    final errors = <String>[];

    void updateSpeed() {
      if (firstToken == null) return;
      final ms = DateTime.now().difference(firstToken!).inMilliseconds;
      final out = usage?.outputTokens ?? liveOut;
      stats.tokensPerSecond = ms > 0 ? out * 1000 / ms : 0;
    }

    final done = Completer<void>();
    final sub = agent
        .send(
          AgentRequest(
            // dsh 会话由 dsh 自己保存上下文，history 只在会话无法恢复时使用
            history: history,
            prompt: prompt,
            // 只续接本服务器上的 dsh 会话：在其他服务器的终端里载入的历史记录新建会话，避免操作错服务器
            externalSessionId: settings.kind != AgentKind.deepseekCli
                ? null
                : (_session!.hostName == hostName ? _session!.externalSessionId : _hereExternalId),
            systemPrompt: systemPrompt,
          ),
        )
        .listen(
          (e) {
            switch (e) {
              case AgentTextDelta(text: final t):
                firstToken ??= DateTime.now();
                stats.firstTokenMs ??= firstToken!.difference(start).inMilliseconds;
                text.write(t);
                if (display) reply.content += t;
                liveOut += estimateTokens(t);
                stats.outputTokens = liveOut;
                updateSpeed();
              case AgentReasoningDelta(text: final t):
                firstToken ??= DateTime.now();
                stats.firstTokenMs ??= firstToken!.difference(start).inMilliseconds;
                reply.reasoning += t;
                liveOut += estimateTokens(t);
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
                _hereExternalId = id;
              case AgentError(:final message):
                errors.add(message);
                messages.add(UiChatMessage('error', message));
            }
            notifyListeners();
          },
          onDone: done.complete,
          onError: (Object e) {
            errors.add('$e');
            messages.add(UiChatMessage('error', '$e'));
            done.complete();
          },
        );
    await done.future;
    await sub.cancel();

    final u = usage;
    reply.inputTokens = u?.inputTokens ?? 0;
    reply.outputTokens = u?.outputTokens ?? liveOut;
    if (display && reply.content.isNotEmpty) {
      await chats.addMessage(sessionId, 'assistant', reply.content, inputTokens: reply.inputTokens, outputTokens: reply.outputTokens);
    } else if (display || text.isEmpty || errors.isNotEmpty) {
      messages.remove(reply);
    }
    for (final err in errors) {
      await chats.addMessage(sessionId, 'error', err);
    }
    // 在其他服务器的终端里续聊时不改写原记录的 dsh 会话（该会话属于原服务器）
    final sameHost = _session!.hostName == hostName;
    await chats.touchSession(sessionId, externalSessionId: sameHost ? externalId : null);
    if (externalId != null) _session = await chats.getSession(sessionId);
    if (u != null || liveOut > 0) {
      await tokens.record(
        agentUuid: settings.uuid,
        agentName: settings.name,
        model: agent.model,
        input: u?.inputTokens ?? 0,
        output: u?.outputTokens ?? liveOut,
      );
    }
    notifyListeners();
    if (errors.isNotEmpty) return null;
    // 没有文本也没有错误：返回空字符串，由调用方决定是否重试
    return text.toString();
  }

  /// 把终端模式下的动作显示为聊天消息（并保存）：说明 + 命令代码块 / 等待提示 / 最终回答
  Future<void> _showAction(TerminalAction a, String raw) async {
    final reply = messages.lastWhere((m) => m.role == 'assistant', orElse: () => UiChatMessage('assistant', ''));
    final content = switch (a.type) {
      TerminalActionType.run => '${a.message.isEmpty ? '' : '${a.message}\n\n'}```bash\n${a.command}\n```',
      TerminalActionType.wait =>
        '${a.message.isEmpty ? '' : '${a.message}\n\n'}_${S.current.t('ai.terminal.waiting', {'n': a.seconds})}_',
      TerminalActionType.answer => a.message,
    };
    if (!messages.contains(reply)) messages.add(reply);
    reply.content = content;
    reply.raw = raw;
    await chats.addMessage(_session!.id, 'assistant', content, inputTokens: reply.inputTokens, outputTokens: reply.outputTokens);
    notifyListeners();
  }

  /// 添加并保存一条消息
  Future<void> _addMessage(String role, String content) async {
    messages.add(UiChatMessage(role, content));
    await chats.addMessage(_session!.id, role, content);
    notifyListeners();
  }

  /// 之前的对话（不保存上下文的 Agent 每次都需要；dsh 只在会话无法恢复时使用）：
  /// AI 回复使用原始文本（保持 JSON 协议格式），终端输出作为用户消息
  List<AgentMessage> _history() => [
    for (final m in messages)
      if (m.role == 'user')
        AgentMessage('user', m.content)
      else if (m.role == 'assistant')
        AgentMessage('assistant', m.raw ?? m.content)
      else if (m.role == 'terminal')
        AgentMessage('user', TerminalAgentProtocol.observation(m.content, afterWait: false)),
  ];

  /// 停止当前任务：停止回答与后续步骤（已在终端中运行的命令不受影响，由用户自己处理）
  void stop() {
    _stop?.stop();
    _agent?.cancel();
  }

  static const _defaultSystemPrompt =
      'You are an assistant embedded in an SSH terminal client. '
      'When suggesting shell commands, put each runnable command in its own ```bash code block. '
      'Be concise.';

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
