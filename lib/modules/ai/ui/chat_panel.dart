import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../app/nav_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../terminal/terminal_agent_driver.dart';
import '../../terminal/terminal_session.dart';
import '../agent_config.dart';
import '../agents_controller.dart';
import '../chat_controller.dart';
import 'agent_model_selector.dart';
import 'chat_message_view.dart';
import 'command_permission_selector.dart';
import 'chat_status_bar.dart';

/// 终端内的 AI 聊天面板：选择 Agent、对话、附带终端上下文、一键把命令发送到终端
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.session});

  final TerminalSession session;

  /// 获取（或创建）会话绑定的聊天控制器：每个终端标签页一个，切换回来继续原对话；
  /// AI 只操作这个终端（即这一台服务器）
  static ChatController controllerFor(BuildContext context, TerminalSession s) {
    final existing = s.uiState['chat'];
    if (existing is ChatController) return existing;
    final services = context.read<AppServices>();
    final c = ChatController(
      chats: services.chatRepo,
      tokens: services.tokenRepo,
      hostName: s.host.name,
      terminal: TerminalAgentDriver(s),
    );
    s.uiState['chat'] = c;
    return c;
  }

  /// 是否为发送快捷键：⌘Enter（macOS）/ Ctrl+Enter（其他平台）；单独按 Enter 只换行，避免误触发送
  static bool isSendKey(LogicalKeyboardKey key, {required bool apple, required bool meta, required bool control}) =>
      (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) && (apple ? meta : control);

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();

  /// macOS 用 ⌘，其他平台用 Ctrl
  bool get _isApple => Theme.of(context).platform == TargetPlatform.macOS;
  late ChatController _chat;

  @override
  void initState() {
    super.initState();
    _chat = ChatPanel.controllerFor(context, widget.session);
    _chat.addListener(_scrollToEnd);
  }

  @override
  void dispose() {
    _chat.removeListener(_scrollToEnd);
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// 本聊天使用的 Agent：有消息后为聊天开始时的 Agent，新对话为全局默认 Agent
  AgentSettings? _agentOf(AgentsController agents) {
    final bound = _chat.boundAgentUuid;
    return (bound == null ? null : agents.agents.where((a) => a.uuid == bound).firstOrNull) ?? agents.active;
  }

  /// 切换 Agent：设为默认 Agent；当前聊天已有消息时新建对话（换 Agent 无法续用原上下文与缓存）
  void _switchAgent(AgentsController agents, String uuid) {
    if (uuid == _agentOf(agents)?.uuid) return;
    agents.setActive(uuid);
    if (_chat.messages.isNotEmpty) _chat.newChat();
  }

  Future<void> _send() async {
    final agent = _agentOf(context.read<AgentsController>());
    final text = _input.text.trim();
    if (agent == null || text.isEmpty) return;
    // 有选区时附带选中内容；终端当前屏幕由 ChatController 自动附上
    final ctx = widget.session.selectedText();
    _input.clear();
    await _chat.send(agent, text, context: ctx);
  }

  /// 把命令发送到终端（不自动回车，由用户确认执行）
  void _runCommand(String cmd) {
    final lines = cmd.trim();
    widget.session.pasteText(lines);
  }

  Future<void> _pickHistory() async {
    final sessions = await context.read<AppServices>().chatRepo.listSessions(limit: 50);
    if (!mounted) return;
    final s = await showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(ctx.tr('ai.history')),
        children: [
          if (sessions.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(ctx.tr('ai.history.empty'))),
          for (final s in sessions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: ListTile(
                dense: true,
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${s.agentName} · ${FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(s.updatedAt))}',
                ),
              ),
            ),
        ],
      ),
    );
    if (s != null) await _chat.loadSession(s);
  }

  @override
  Widget build(BuildContext context) {
    final agents = context.watch<AgentsController>();
    final theme = Theme.of(context);
    if (agents.agents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 40),
              const SizedBox(height: 12),
              Text(context.tr('ai.no_agent'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => context.read<NavController>().go(AppPage.settings),
                child: Text(context.tr('ai.configure')),
              ),
            ],
          ),
        ),
      );
    }
    final active = _agentOf(agents)!;
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                // 当前聊天的标题（新对话显示“新对话”）
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      _chat.session?.title ?? context.tr('ai.chat.untitled'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('ai.history'),
                  icon: const Icon(Icons.history, size: 18),
                  onPressed: _chat.busy ? null : _pickHistory,
                ),
                IconButton(
                  tooltip: context.tr('ai.new_chat'),
                  icon: const Icon(Icons.add_comment_outlined, size: 18),
                  onPressed: _chat.busy ? null : _chat.newChat,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _chat.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        context.tr('ai.empty_hint'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: _chat.messages.length,
                    itemBuilder: (context, i) => ChatMessageView(message: _chat.messages[i], onRunCommand: _runCommand),
                  ),
          ),
          if (_chat.waitingForEnter) _EnterHint(),
          const Divider(height: 1),
          ChatStatusBar(stats: _chat.stats, busy: _chat.busy),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    // 由谁回答：Agent、模型、推理强度（回答中不能切换；换 Agent 新建对话）
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AgentModelSelector(
                          agents: agents.agents,
                          agent: active,
                          enabled: !_chat.busy,
                          onAgentChanged: (uuid) => _switchAgent(agents, uuid),
                        ),
                      ),
                    ),
                    CommandPermissionSelector(
                      value: _chat.permission,
                      onChanged: (p) => _chat.permission = p,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // ⌘Enter（macOS）/ Ctrl+Enter 发送；单独按 Enter 换行，避免误触发送
                Focus(
                  onKeyEvent: (node, e) {
                    final k = HardwareKeyboard.instance;
                    if (e is KeyDownEvent &&
                        ChatPanel.isSendKey(
                          e.logicalKey,
                          apple: _isApple,
                          meta: k.isMetaPressed,
                          control: k.isControlPressed,
                        )) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: context.tr('ai.input_hint', {'key': _isApple ? '⌘Enter' : 'Ctrl+Enter'}),
                      suffixIcon: _chat.busy
                          ? IconButton(icon: const Icon(Icons.stop_circle_outlined), onPressed: _chat.stop)
                          : IconButton(icon: const Icon(Icons.send), onPressed: _send),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 逐条确认时的提示：命令已填入终端，等待用户检查后按回车
class _EnterHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.keyboard_return_rounded, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(context.tr('ai.terminal.press_enter'), style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
