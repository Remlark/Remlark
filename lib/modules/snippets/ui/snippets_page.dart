import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../../utils/ui_utils.dart';
import '../snippet_model.dart';
import 'snippet_editor_dialog.dart';

/// 快捷指令管理页
class SnippetsPage extends StatefulWidget {
  const SnippetsPage({super.key});

  @override
  State<SnippetsPage> createState() => _SnippetsPageState();
}

class _SnippetsPageState extends State<SnippetsPage> {
  List<SnippetEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await context.read<AppServices>().snippetRepo.list();
    if (mounted) setState(() => _items = v);
  }

  Future<void> _edit([SnippetEntry? s]) async {
    final r = await showDialog<SnippetEntry>(
      context: context,
      builder: (_) => SnippetEditorDialog(existing: s, nextOrder: _items.length),
    );
    if (r == null || !mounted) return;
    await context.read<AppServices>().snippetRepo.save(r);
    _load();
  }

  /// 拖动排序后重写 sortOrder
  Future<void> _reorder(int oldIndex, int newIndex) async {
    final list = List.of(_items);
    list.insert(newIndex, list.removeAt(oldIndex));
    setState(() => _items = list);
    final repo = context.read<AppServices>().snippetRepo;
    for (var i = 0; i < list.length; i++) {
      final s = list[i];
      if (s.sortOrder != i) {
        await repo.save(
          SnippetEntry(
            uuid: s.uuid,
            name: s.name,
            content: s.content,
            kind: s.kind,
            autoEnter: s.autoEnter,
            sortOrder: i,
          ),
        );
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 20, 14),
          child: Row(
            children: [
              Text(context.tr('nav.snippets'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr('snippet.page.hint'),
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.tr('snippet.new')),
                onPressed: () => _edit(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _items.isEmpty
              ? Center(child: Text(context.tr('snippet.empty')))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _items.length,
                  onReorderItem: _reorder,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, i) {
                    final s = _items[i];
                    return Padding(
                      key: ValueKey(s.uuid),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: Icon(s.isAction ? Icons.auto_fix_high : Icons.short_text),
                          ),
                          title: Text(s.name),
                          subtitle: Text(
                            s.isAction ? context.tr('snippet.kind.install_key.desc') : s.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: s.isAction ? null : const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                          onTap: () => _edit(s),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final ok = await UiUtils.confirm(
                                context,
                                title: context.tr('snippet.delete'),
                                message: s.name,
                                danger: true,
                              );
                              if (!ok || !context.mounted) return;
                              await context.read<AppServices>().snippetRepo.delete(s.uuid);
                              _load();
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
