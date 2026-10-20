import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';
import '../app/theme/app_theme.dart';

/// 统一页面头：大标题 + 副标题 + 右侧操作。所有一级页面使用同一尺寸与间距，保证布局一致
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;

  /// 右侧操作按钮（一个任务区只放一个主要按钮）
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.pagePadding, 22, 24, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: p.text, height: 1.2),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: p.textMuted),
                  ),
                ],
              ],
            ),
          ),
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(width: 10), actions[i]],
        ],
      ),
    );
  }
}

/// 页面框架：页面头 +（可选的页头下方内容，如分页标签）+ 分隔线 + 内容区
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.header, required this.body, this.headerBottom});

  final Widget header;
  final Widget body;

  /// 页头与分隔线之间的内容
  final Widget? headerBottom;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          ?headerBottom,
          const Divider(height: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// 区块标题（设置分区、编辑弹窗分区等）：标题 + 可选说明
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, this.description, this.trailing, this.large = false});

  final String title;
  final String? description;
  final Widget? trailing;

  /// 大号标题（设置分区顶部）
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: large ? 22 : 16, fontWeight: FontWeight.w700, color: p.text),
              ),
              if (description != null) ...[
                SizedBox(height: large ? 6 : 4),
                Text(description!, style: TextStyle(fontSize: 13, color: p.textMuted)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
