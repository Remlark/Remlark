import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/format_utils.dart';
import '../chat_controller.dart';

/// 聊天状态栏：输出速度（去除首字延迟）、输入 / 输出 / 上下文 token
class ChatStatusBar extends StatelessWidget {
  const ChatStatusBar({super.key, required this.stats, required this.busy});

  final ChatStats stats;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline);
    final approx = stats.estimated ? '≈' : '';
    final items = <(IconData, String, String)>[
      (Icons.speed, context.tr('ai.stats.speed'), '${stats.tokensPerSecond.toStringAsFixed(1)} tok/s'),
      (Icons.arrow_upward, context.tr('ai.stats.input'), '$approx${FormatUtils.tokens(stats.inputTokens)}'),
      (Icons.arrow_downward, context.tr('ai.stats.output'), '$approx${FormatUtils.tokens(stats.outputTokens)}'),
      (Icons.memory, context.tr('ai.stats.context'), '$approx${FormatUtils.tokens(stats.contextTokens)}'),
      if (stats.firstTokenMs != null)
        (Icons.timer_outlined, context.tr('ai.stats.first_token'), '${stats.firstTokenMs} ms'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Wrap(
        spacing: 12,
        children: [
          if (busy) const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
          for (final (icon, tip, value) in items)
            Tooltip(
              message: tip,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: style?.color),
                  const SizedBox(width: 2),
                  Text(value, style: style),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
