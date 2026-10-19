import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../chat_controller.dart';

/// 单条聊天消息：Markdown 渲染，代码块带“复制”与“发送到终端”按钮
class ChatMessageView extends StatelessWidget {
  const ChatMessageView({super.key, required this.message, this.onRunCommand});

  final UiChatMessage message;

  /// 把代码块发送到终端（为空时不显示该按钮，例如历史记录查看）
  final void Function(String command)? onRunCommand;

  /// 拆分 Markdown 文本中的代码块
  static List<(bool isCode, String lang, String text)> split(String s) {
    final out = <(bool, String, String)>[];
    final re = RegExp(r'```([\w+-]*)\n([\s\S]*?)(```|$)');
    var last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) out.add((false, '', s.substring(last, m.start)));
      out.add((true, m.group(1) ?? '', m.group(2)!.trimRight()));
      last = m.end;
    }
    if (last < s.length) out.add((false, '', s.substring(last)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = message;
    if (m.role == 'error') {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: SelectableText(m.content, style: const TextStyle(color: Colors.red, fontSize: 12)),
      );
    }
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.reasoning.isNotEmpty)
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(context.tr('ai.reasoning'), style: theme.textTheme.labelMedium),
                  children: [Text(m.reasoning, style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline))],
                ),
              ),
            if (m.content.isEmpty && m.role == 'assistant')
              const Padding(
                padding: EdgeInsets.all(4),
                child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            for (final (isCode, lang, text) in split(m.content))
              if (isCode)
                _CodeBlock(code: text, lang: lang, onRun: onRunCommand)
              else if (text.trim().isNotEmpty)
                MarkdownBody(
                  data: text,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                    p: theme.textTheme.bodyMedium,
                    code: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.code, required this.lang, this.onRun});

  final String code;
  final String lang;
  final void Function(String)? onRun;

  bool get _isShell => const ['', 'bash', 'sh', 'shell', 'zsh', 'console'].contains(lang.toLowerCase());

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFF1E1F24), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: Row(
              children: [
                Text(lang.isEmpty ? 'code' : lang, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                const Spacer(),
                IconButton(
                  tooltip: context.tr('common.copy'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, size: 14, color: Colors.white70),
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                ),
                if (onRun != null && _isShell)
                  IconButton(
                    tooltip: context.tr('ai.run_in_terminal'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.greenAccent),
                    onPressed: () => onRun!(code),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
