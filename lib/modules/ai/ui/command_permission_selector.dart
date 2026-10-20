import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../../ui_kit/app_menu.dart';
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
    return AppMenuAnchor<CommandPermission>(
      selected: mode,
      // 触发按钮较窄，菜单需要容纳说明文字
      minWidth: 300,
      maxWidth: 320,
      onSelected: onChanged,
      items: (context) => [
        for (final m in CommandPermission.values)
          AppMenuItem(
            value: m,
            icon: _icon(m),
            iconColor: m == CommandPermission.autoAll ? p.warning : null,
            label: context.tr(_key(m)),
            description: context.tr('${_key(m)}.desc'),
          ),
      ],
      builder: (context, open) => Tooltip(
        message: context.tr('ai.perm.tooltip'),
        child: InkWell(
          onTap: open,
          borderRadius: BorderRadius.circular(6),
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
        ),
      ),
    );
  }
}
