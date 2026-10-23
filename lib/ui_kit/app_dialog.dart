import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';
import '../app/theme/app_theme.dart';
import '../l10n/app_localizations.dart';

/// 统一弹窗：标题（可带图标）与关闭入口固定在顶部，正文可滚动，操作栏固定在底部，
/// 取消位于主要操作左侧。所有业务弹窗都使用该模板
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.icon,
    this.iconColor,
    this.width = 460,
    this.scrollable = true,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 4, 24, 20),
    this.headerExtra,
    this.subtitle,
  });

  final String title;
  final Widget content;

  /// 底部操作（从左到右：取消、主要操作）
  final List<Widget> actions;

  /// 标题左侧图标（如删除确认的垃圾桶）
  final IconData? icon;
  final Color? iconColor;
  final double width;

  /// 正文是否包在滚动视图中（正文自带滚动 / 固定高度时设为 false）
  final bool scrollable;
  final EdgeInsetsGeometry contentPadding;

  /// 标题右侧附加内容（如协议切换）
  final Widget? headerExtra;

  /// 可选说明文字，与标题共用固定头部，避免正文被重复留白挤压。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = iconColor ?? p.accent;
    final body = Padding(padding: contentPadding, child: content);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
              child: Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(AppSizes.radius),
                      ),
                      child: Icon(icon, color: c, size: 22),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.text),
                              ),
                            ),
                            if (headerExtra != null) ...[const SizedBox(width: 20), headerExtra!],
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 6),
                          Text(subtitle!, style: TextStyle(fontSize: 13, color: p.textMuted)),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('common.close'),
                    icon: Icon(Icons.close, size: 20, color: p.textMuted),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ),
            Flexible(child: scrollable ? SingleChildScrollView(child: body) : body),
            if (actions.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10), actions[i]],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
