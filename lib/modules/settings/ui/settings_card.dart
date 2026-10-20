import 'package:flutter/material.dart';

import '../../../app/theme/app_palette.dart';
import '../../../ui_kit/page_header.dart';

/// 设置分区：大标题 + 说明 + 设置行
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.title, required this.children, this.description, this.trailing});

  final String title;
  final String? description;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(title: title, description: description, trailing: trailing, large: true),
        const SizedBox(height: 18),
        const Divider(height: 1),
        ...children,
        const SizedBox(height: 28),
      ],
    );
  }
}

/// 设置小节标题（同一分区内的分组，如“终端”）
class SettingsGroupTitle extends StatelessWidget {
  const SettingsGroupTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
      ),
    );
  }
}

/// 设置行：左侧标签与说明，右侧控件；底部细分隔线
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.label, required this.child, this.description, this.stacked = false});

  final String label;
  final String? description;
  final Widget child;

  /// 控件放在标签下方（宽控件，如表单）
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.text),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: TextStyle(fontSize: 13, color: p.textMuted)),
        ],
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: stacked
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, const SizedBox(height: 12), child])
          : Row(
              children: [
                Expanded(flex: 2, child: text),
                const SizedBox(width: 24),
                Flexible(
                  flex: 3,
                  child: Align(alignment: Alignment.centerRight, child: child),
                ),
              ],
            ),
    );
  }
}
