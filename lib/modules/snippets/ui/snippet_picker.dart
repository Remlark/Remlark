import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../snippet_model.dart';

/// 快捷指令选择弹窗：可搜索，回车选择第一项
class SnippetPicker extends StatefulWidget {
  const SnippetPicker({super.key});

  /// 显示选择器，返回选中的快捷指令
  static Future<SnippetEntry?> show(BuildContext context) {
    return showDialog<SnippetEntry>(
      context: context,
      builder: (_) =>
          const Dialog(alignment: Alignment.topCenter, insetPadding: EdgeInsets.only(top: 80), child: SnippetPicker()),
    );
  }

  @override
  State<SnippetPicker> createState() => _SnippetPickerState();
}

class _SnippetPickerState extends State<SnippetPicker> {
  List<SnippetEntry> _all = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    context.read<AppServices>().snippetRepo.list().then((v) {
      if (mounted) setState(() => _all = v);
    });
  }

  List<SnippetEntry> get _filtered {
    final q = _q.toLowerCase();
    return _all.where((s) => s.name.toLowerCase().contains(q) || s.content.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return SizedBox(
      width: 520,
      height: 420,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.bolt, size: 18),
                hintText: context.tr('snippet.search'),
              ),
              onChanged: (v) => setState(() => _q = v),
              onSubmitted: (_) {
                if (items.isNotEmpty) Navigator.pop(context, items.first);
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(context.tr('snippet.empty')))
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final s = items[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(s.isAction ? Icons.auto_fix_high : Icons.short_text, size: 18),
                        title: Text(s.name),
                        subtitle: s.isAction
                            ? Text(context.tr('snippet.kind.install_key'))
                            : Text(
                                s.content,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                              ),
                        onTap: () => Navigator.pop(context, s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
