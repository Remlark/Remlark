import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../data/database.dart';
import '../../../l10n/app_localizations.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Text(context.tr('ai.history.count', {'n': _sessions.length}), style: theme.textTheme.labelMedium),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.refresh, size: 18), onPressed: _load),
                  ],
                ),
              ),
              Expanded(
                child: _sessions.isEmpty
                    ? Center(child: Text(context.tr('ai.history.empty')))
                    : ListView.builder(
                        itemCount: _sessions.length,
                        itemBuilder: (context, i) {
                          final s = _sessions[i];
                          return ListTile(
                            selected: _selected?.id == s.id,
                            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${s.agentName}${s.hostName.isEmpty ? '' : ' · ${s.hostName}'}\n${FormatUtils.dateTime(DateTime.fromMillisecondsSinceEpoch(s.updatedAt))}',
                              style: theme.textTheme.labelSmall,
                            ),
                            isThreeLine: true,
                            onTap: () => _open(s),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => _delete(s),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selected == null
              ? Center(child: Text(context.tr('ai.history.select')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [for (final m in _messages) ChatMessageView(message: UiChatMessage(m.role, m.content))],
                ),
        ),
      ],
    );
  }
}
