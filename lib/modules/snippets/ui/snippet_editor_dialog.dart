import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_dialog.dart';
import '../../../ui_kit/app_menu.dart';
import '../../../ui_kit/panel.dart';
import '../../../utils/id_utils.dart';
import '../../../utils/platform_utils.dart';
import '../snippet_model.dart';
import '../../../ui_kit/check_label.dart';

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
    return AppDialog(
      title: context.tr(widget.existing == null ? 'snippet.new' : 'snippet.edit'),
      width: 560,
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(context.tr('snippet.kind')),
            AppDropdown<SnippetKind>(
              value: _kind,
              items: [
                AppMenuItem(value: SnippetKind.text, label: context.tr('snippet.kind.text')),
                if (PlatformUtils.isUnixDesktop || _kind == SnippetKind.installSystemKey)
                  AppMenuItem(value: SnippetKind.installSystemKey, label: context.tr('snippet.kind.install_key')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? SnippetKind.text),
            ),
            const SizedBox(height: 16),
            FieldLabel(context.tr('snippet.name'), required: true),
            TextField(controller: _name, autofocus: true),
            const SizedBox(height: 16),
            if (_kind == SnippetKind.text) ...[
              FieldLabel(context.tr('snippet.content')),
              TextField(
                controller: _content,
                maxLines: 5,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              CheckLabel(
                value: _autoEnter,
                onChanged: (v) => setState(() => _autoEnter = v),
                label: context.tr('snippet.auto_enter'),
              ),
            ] else
              Text(context.tr('snippet.kind.install_key.desc'), style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
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
