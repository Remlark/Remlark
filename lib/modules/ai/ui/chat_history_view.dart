import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../data/database.dart';
import '../../../app/theme/app_palette.dart';
import '../../../app/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/buttons.dart';
import '../../../ui_kit/panel.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/ui_utils.dart';
import '../chat_controller.dart';
import 'chat_message_view.dart';

/// 聊天记录：左侧会话列表，右侧消息详情，可删除
class ChatHistoryView extends StatefulWidget {
  const ChatHistoryView({super.key});

  @override
  State<ChatHistoryView> createState() => _ChatHistoryViewState();
}

class _ChatHistoryViewState extends State<ChatHistoryView> {
  List<ChatSession> _sessions = [];
  ChatSession? _selected;
  List<ChatMessage> _messages = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await context.read<AppServices>().chatRepo.listSessions();
    if (!mounted) return;
    setState(() {
      _sessions = s;
      if (_selected != null && !s.any((e) => e.id == _selected!.id)) {
        _selected = null;
        _messages = [];
      }
    });
  }

  Future<void> _open(ChatSession s) async {
    final m = await context.read<AppServices>().chatRepo.messages(s.id);
    if (!mounted) return;
    setState(() {
      _selected = s;
      _messages = m;
    });
  }

  Future<void> _delete(ChatSession s) async {
    final ok = await UiUtils.confirm(context, title: context.tr('ai.history.delete'), message: s.title, danger: true);
    if (!ok || !mounted) return;
    await context.read<AppServices>().chatRepo.deleteSession(s.id);
    await _load();
  }

  /// 日期分组：今天 / 昨天 / 更早
  String _bucket(BuildContext context, int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!d.isBefore(today)) return context.tr('ai.history.today');
    if (!d.isBefore(today.subtract(const Duration(days: 1)))) return context.tr('ai.history.yesterday');
    return context.tr('ai.history.earlier');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = _q.trim().toLowerCase();
    final list = _sessions
        .where((s) => q.isEmpty || s.title.toLowerCase().contains(q) || s.hostName.toLowerCase().contains(q))
        .toList();
    final children = <Widget>[];
    String? last;
    for (final s in list) {
      final b = _bucket(context, s.updatedAt);
      if (b != last) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: Text(
              b,
              style: TextStyle(fontSize: 12, color: p.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
        );
        last = b;
      }
      children.add(
        _SessionTile(session: s, selected: _selected?.id == s.id, onTap: () => _open(s), onDelete: () => _delete(s)),
      );
    }
    final sel = _selected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 340,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: p.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: SearchField(hint: context.tr('ai.history.search'), onChanged: (v) => setState(() => _q = v)),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(context.tr('ai.history.empty'), style: TextStyle(color: p.textFaint)),
                      )
                    : ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 12), children: children),
              ),
            ],
          ),
        ),
        Expanded(
          child: sel == null
              ? EmptyState(icon: Icons.forum_outlined, title: context.tr('ai.history.select'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 20, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sel.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  [
                                    if (sel.hostName.isNotEmpty) sel.hostName,
                                    sel.agentName,
                                    FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(sel.updatedAt)),
                                  ].join('  ·  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: p.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ToolButton(
                            compact: true,
                            icon: Icons.delete_outline,
                            label: context.tr('ai.history.delete'),
                            onPressed: () => _delete(sel),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          for (final m in _messages) ChatMessageView(message: UiChatMessage(m.role, m.content)),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 会话列表项：标题、主机、时间，悬停显示删除
class _SessionTile extends StatefulWidget {
  const _SessionTile({required this.session, required this.selected, required this.onTap, required this.onDelete});

  final ChatSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends State<_SessionTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.session;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            color: widget.selected ? p.accentSoft : (_hover ? p.hover : null),
            borderRadius: BorderRadius.circular(AppSizes.radius),
            border: Border(left: BorderSide(color: widget.selected ? p.accent : Colors.transparent, width: 3)),
          ),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 18, color: widget.selected ? p.accent : p.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.text),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (s.hostName.isNotEmpty) s.hostName,
                        FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(s.updatedAt)),
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textMuted),
                    ),
                  ],
                ),
              ),
              Opacity(
                opacity: _hover || widget.selected ? 1 : 0,
                child: GhostIconButton(
                  icon: Icons.delete_outline,
                  tooltip: context.tr('ai.history.delete'),
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
