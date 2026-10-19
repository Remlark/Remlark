import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/id_utils.dart';
import '../../../utils/platform_utils.dart';
import '../snippet_model.dart';

/// 快捷指令编辑对话框
class SnippetEditorDialog extends StatefulWidget {
  const SnippetEditorDialog({super.key, this.existing, required this.nextOrder});

  final SnippetEntry? existing;
  final int nextOrder;

  @override
  State<SnippetEditorDialog> createState() => _SnippetEditorDialogState();
}

class _SnippetEditorDialogState extends State<SnippetEditorDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _content = TextEditingController(text: widget.existing?.content ?? '');
  late SnippetKind _kind = widget.existing?.kind ?? SnippetKind.text;
  late bool _autoEnter = widget.existing?.autoEnter ?? true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr(widget.existing == null ? 'snippet.new' : 'snippet.edit')),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<SnippetKind>(
              initialValue: _kind,
              decoration: InputDecoration(labelText: context.tr('snippet.kind')),
              items: [
                DropdownMenuItem(value: SnippetKind.text, child: Text(context.tr('snippet.kind.text'))),
                if (PlatformUtils.isUnixDesktop || _kind == SnippetKind.installSystemKey)
                  DropdownMenuItem(
                    value: SnippetKind.installSystemKey,
                    child: Text(context.tr('snippet.kind.install_key')),
                  ),
              ],
              onChanged: (v) => setState(() => _kind = v ?? SnippetKind.text),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: context.tr('snippet.name')),
            ),
            const SizedBox(height: 12),
            if (_kind == SnippetKind.text) ...[
              TextField(
                controller: _content,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(labelText: context.tr('snippet.content'), alignLabelWithHint: true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _autoEnter,
                onChanged: (v) => setState(() => _autoEnter = v ?? true),
                title: Text(context.tr('snippet.auto_enter')),
              ),
            ] else
              Text(context.tr('snippet.kind.install_key.desc'), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        FilledButton(
          onPressed: () {
            if (_name.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              SnippetEntry(
                uuid: widget.existing?.uuid ?? IdUtils.newId(),
                name: _name.text.trim(),
                content: _kind == SnippetKind.text ? _content.text : '',
                kind: _kind,
                autoEnter: _autoEnter,
                sortOrder: widget.existing?.sortOrder ?? widget.nextOrder,
              ),
            );
          },
          child: Text(context.tr('common.save')),
        ),
      ],
    );
  }
}
