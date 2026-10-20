import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../terminal_agent/command_permission.dart';

/// 聊天底部的命令权限选择：只给建议 / 逐条确认 / 只读自动执行 / 全部自动执行。
/// 每个终端标签页独立，“全部自动执行”以警示色显示
class CommandPermissionSelector extends StatelessWidget {
  const CommandPermissionSelector({super.key, required this.value, required this.onChanged});

  final CommandPermission value;
  final ValueChanged<CommandPermission> onChanged;

  /// 各模式的图标
  static IconData _icon(CommandPermission m) => switch (m) {
    CommandPermission.suggestOnly => Icons.lightbulb_outline_rounded,
    CommandPermission.ask => Icons.back_hand_outlined,
    CommandPermission.autoReadOnly => Icons.visibility_outlined,
    CommandPermission.autoAll => Icons.bolt_rounded,
  };

  /// 文本 key 前缀
  static String _key(CommandPermission m) => 'ai.perm.${m.name}';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mode = value;
    final color = mode == CommandPermission.autoAll ? p.warning : p.textMuted;
    return PopupMenuButton<CommandPermission>(
      tooltip: context.tr('ai.perm.tooltip'),
      initialValue: mode,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final m in CommandPermission.values)
          PopupMenuItem(
            value: m,
            child: SizedBox(
              width: 260,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(_icon(m), size: 18, color: m == CommandPermission.autoAll ? p.warning : p.textMuted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(_key(m)),
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.text),
                        ),
                        const SizedBox(height: 2),
                        Text(context.tr('${_key(m)}.desc'), style: TextStyle(fontSize: 12, color: p.textMuted)),
                      ],
                    ),
                  ),
                  if (m == mode) Icon(Icons.check_rounded, size: 18, color: p.accent),
                ],
              ),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(mode), size: 15, color: color),
            const SizedBox(width: 4),
            Text(context.tr(_key(mode)), style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w500)),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}
