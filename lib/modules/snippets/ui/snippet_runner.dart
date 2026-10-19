import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_services.dart';
import '../../../l10n/app_localizations.dart';
import '../../terminal/terminal_session.dart';
import '../snippet_action.dart';
import '../snippet_model.dart';

/// 快捷指令执行器：普通指令直接输入，特殊动作显示执行过程对话框
class SnippetRunner {
  SnippetRunner._();

  static Future<void> run(BuildContext context, SnippetEntry snippet, TerminalSession session) async {
    final action = SnippetAction.forSnippet(snippet);
    final hosts = context.read<AppServices>().hostRepo;
    if (!action.showsProgress) {
      await action.run(SnippetContext(session: session, hosts: hosts, log: (_) {}));
      return;
    }
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ActionProgressDialog(
        title: snippet.name,
        task: (log) => action.run(SnippetContext(session: session, hosts: hosts, log: log)),
      ),
    );
  }
}

class _ActionProgressDialog extends StatefulWidget {
  const _ActionProgressDialog({required this.title, required this.task});

  final String title;
  final Future<void> Function(void Function(String) log) task;

  @override
  State<_ActionProgressDialog> createState() => _ActionProgressDialogState();
}

class _ActionProgressDialogState extends State<_ActionProgressDialog> {
  final List<String> _lines = [];
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget
        .task((l) => setState(() => _lines.add(l)))
        .then(
          (_) {
            if (mounted) setState(() => _done = true);
          },
          onError: (Object e) {
            if (mounted) {
              setState(() {
                _done = true;
                _error = '$e';
              });
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          if (!_done) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          if (_done)
            Icon(_error == null ? Icons.check_circle : Icons.error, color: _error == null ? Colors.green : Colors.red),
          const SizedBox(width: 10),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: Container(
        width: 520,
        constraints: const BoxConstraints(minHeight: 120),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
        child: SelectableText(
          [..._lines, if (_error != null) '✗ $_error'].join('\n'),
          style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 12),
        ),
      ),
      actions: [
        FilledButton(onPressed: _done ? () => Navigator.pop(context) : null, child: Text(context.tr('common.close'))),
      ],
    );
  }
}
