import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';
import '../app/theme/app_theme.dart';

/// 工具栏按钮：描边样式，图标 + 文字；选中时为强调色浅底与描边。
/// 用于会话工具栏、视图切换等
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.selected = false,
    this.tooltip,
    this.compact = false,
    this.trailing,
    this.color,
  });

  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool selected;
  final String? tooltip;

  /// 紧凑高度（会话内工具栏）
  final bool compact;

  /// 文字后附加内容（如下拉箭头）
  final Widget? trailing;

  /// 自定义语义色；选中时同时用于底色与边框（如广播警示）。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null;
    final fg = !enabled ? p.textFaint : (color ?? (selected ? p.accent : p.text));
    final h = compact ? AppSizes.controlCompact : AppSizes.control;
    Widget btn = Material(
      color: selected ? (color?.withValues(alpha: 0.10) ?? p.accentSoft) : p.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.radius),
        side: BorderSide(color: selected ? (color ?? p.accent).withValues(alpha: 0.7) : p.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        hoverColor: p.hover,
        child: SizedBox(
          height: h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : (compact ? 10 : 14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label == null)
                  SizedBox(
                    width: h,
                    child: Icon(icon, size: 17, color: fg),
                  )
                else ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: compact ? 13 : 14, color: fg, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
                if (trailing != null) ...[const SizedBox(width: 6), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) btn = Tooltip(message: tooltip!, child: btn);
    return Semantics(button: true, selected: selected, label: label ?? tooltip, child: btn);
  }
}

/// 无边框的小图标按钮（卡片“更多”、表格行操作等），带 tooltip
class GhostIconButton extends StatelessWidget {
  const GhostIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 32,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: size * 0.55,
          color: color ?? p.textMuted,
          disabledColor: p.textFaint,
          onPressed: onPressed,
          icon: Icon(icon),
        ),
      ),
    );
  }
}

/// 分离式选择按钮组（筛选：全部 / SSH / RDP / VNC），每项独立描边，选中项强调色
class PillChoice<T> extends StatelessWidget {
  const PillChoice({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  /// (值, 文本)
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (v, label) in items)
          Material(
            color: v == value ? p.accentSoft : p.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radius),
              side: BorderSide(color: v == value ? p.accent.withValues(alpha: 0.7) : p.borderStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onChanged(v),
              child: Container(
                height: compact ? AppSizes.controlCompact : AppSizes.control,
                constraints: const BoxConstraints(minWidth: 64),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: v == value ? p.accent : p.text,
                    fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 图标切换组（网格 / 列表视图），相邻按钮连为一体
class IconToggleGroup<T> extends StatelessWidget {
  const IconToggleGroup({super.key, required this.items, required this.value, required this.onChanged});

  /// (值, 图标, tooltip)
  final List<(T, IconData, String)> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: AppSizes.control,
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: p.borderStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, icon, tip) in items)
            Tooltip(
              message: tip,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSizes.radius - 1),
                onTap: () => onChanged(v),
                child: Container(
                  width: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: v == value ? p.accentSoft : null,
                    borderRadius: BorderRadius.circular(AppSizes.radius - 1),
                    border: v == value ? Border.all(color: p.accent.withValues(alpha: 0.7)) : null,
                  ),
                  child: Icon(icon, size: 18, color: v == value ? p.accent : p.textMuted),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 危险操作按钮（仅在确认阶段使用）
class DangerButton extends StatelessWidget {
  const DangerButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: p.danger, foregroundColor: Colors.white),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
