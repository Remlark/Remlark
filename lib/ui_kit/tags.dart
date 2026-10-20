import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';

/// 小标签：描边 + 浅色底，用于协议（SSH / RDP / VNC / SFTP）、密钥类型、指令类型
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.small = false});

  final String text;

  /// 标签颜色，默认次文字色
  final Color? color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.textMuted;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 5 : 8, vertical: small ? 1 : 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.isDark ? 0.10 : 0.08),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(fontSize: small ? 10 : 11.5, fontWeight: FontWeight.w600, color: c, height: 1.3),
      ),
    );
  }
}

/// 状态文本：图标 / 圆点 + 文字（状态不能只靠颜色表达）
class StatusText extends StatelessWidget {
  const StatusText({super.key, required this.text, required this.color, this.icon, this.fontSize = 13});

  final String text;
  final Color color;

  /// 为空时显示圆点
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: fontSize + 5, color: color)
        else
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, color: color, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// 键帽（快捷键提示）
class KeyCap extends StatelessWidget {
  const KeyCap(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: p.input,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: p.borderStrong),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: p.text, fontFamily: 'monospace'),
      ),
    );
  }
}
