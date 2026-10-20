import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';
import '../app/theme/app_theme.dart';

/// 统一面板：面板底色 + 细描边 + 12px 圆角
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.highlighted = false});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 选中 / 聚焦时使用强调色描边
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        border: Border.all(color: highlighted ? p.accent.withValues(alpha: 0.8) : p.border),
      ),
      child: child,
    );
  }
}

/// 空状态：图标 + 标题 + 说明 + 可选操作
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.panel,
                borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
                border: Border.all(color: p.borderStrong),
              ),
              child: Icon(icon, size: 28, color: p.accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: p.text),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: p.textMuted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

/// 搜索框：前置搜索图标，统一高度
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.hint, required this.onChanged, this.controller, this.width});

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = SizedBox(
      height: AppSizes.control,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 19),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// 表单字段标签（输入框上方），必填时显示星号
/// 带上方标签的表单字段：标签 + 输入控件 + 可选说明文字，表单内统一使用，保证并排字段顶部对齐
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child, this.helper, this.required = false});

  final String label;
  final Widget child;

  /// 输入框下方的说明文字
  final String? helper;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label, required: required),
        child,
        if (helper != null) FieldHelper(helper!),
      ],
    );
  }
}

/// 表单说明文字（字段或选项下方的灰色小字）
class FieldHelper extends StatelessWidget {
  const FieldHelper(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text, style: TextStyle(fontSize: 12, color: context.palette.textFaint)),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (required)
              TextSpan(
                text: ' *',
                style: TextStyle(color: p.danger),
              ),
          ],
        ),
        style: TextStyle(fontSize: 13, color: p.textMuted, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// 警示条：页面顶部的提示（图标 + 文字 + 可选操作按钮），用于需要用户处理的状态（如远程已锁屏）
class WarningBar extends StatelessWidget {
  const WarningBar({super.key, required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.14),
        border: Border(bottom: BorderSide(color: p.warning.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: p.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 13, color: p.text)),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
}
