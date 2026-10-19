import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../app/nav_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../../terminal/terminal_session.dart';
import '../agents_controller.dart';
import '../chat_controller.dart';
import 'chat_message_view.dart';
import 'chat_status_bar.dart';

/// 终端内的 AI 聊天面板：选择 Agent、对话、附带终端上下文、一键把命令发送到终端
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.session});

  final TerminalSession session;

  /// 获取（或创建）会话绑定的聊天控制器
  static ChatController controllerFor(BuildContext context, TerminalSession s) {
    final existing = s.uiState['chat'];
    if (existing is ChatController) return existing;
    final services = context.read<AppServices>();
    final c = ChatController(chats: services.chatRepo, tokens: services.tokenRepo, hostName: s.host.name);
    s.uiState['chat'] = c;
    return c;
  }

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  bool _attachOutput = false;
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

  Future<void> _send() async {
    final agent = context.read<AgentsController>().active;
    final text = _input.text.trim();
    if (agent == null || text.isEmpty) return;
    String? ctx;
    final sel = widget.session.selectedText();
    if (sel != null) {
      ctx = sel;
    } else if (_attachOutput) {
      ctx = widget.session.recentText();
    }
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
    final active = agents.active!;
    return ListenableBuilder(
      listenable: _chat,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      isDense: true,
                      value: active.uuid,
                      items: [
                        for (final a in agents.agents)
                          DropdownMenuItem(
                            value: a.uuid,
                            child: Text(a.name, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _chat.busy ? null : (v) => v == null ? null : agents.setActive(v),
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
          const Divider(height: 1),
          ChatStatusBar(stats: _chat.stats, busy: _chat.busy),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(context.tr('ai.attach_output'), style: const TextStyle(fontSize: 11)),
                      selected: _attachOutput,
                      onSelected: (v) => setState(() => _attachOutput = v),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.tr('ai.selection_hint'),
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Focus(
                  onKeyEvent: (node, e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
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
                      hintText: context.tr('ai.input_hint'),
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
