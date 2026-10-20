import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';
import '../app/theme/app_theme.dart';

/// 统一导航项：应用导航、主机分组、设置分区等共用。
/// 选中时显示左侧强调色竖条与浅底，图标与文字使用强调色
class NavTile extends StatefulWidget {
  const NavTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.onSecondaryTapUp,
    this.height = 44,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 右侧附加内容（数量、徽标）
  final Widget? trailing;

  /// 右键菜单
  final GestureTapUpCallback? onSecondaryTapUp;
  final double height;

  @override
  State<NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<NavTile> {
  bool _hover = false;

  /// 悬停动画时长与曲线
  static const _duration = Duration(milliseconds: 180);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sel = widget.selected;
    return Semantics(
      selected: sel,
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapUp: widget.onSecondaryTapUp,
          // 用 0→1 的悬停进度统一驱动背景、边框、投影、竖条、位移与颜色，保证各部分同步
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _hover ? 1 : 0),
            duration: _duration,
            curve: _curve,
            builder: (context, t, _) => _buildTile(p, sel, t),
          ),
        ),
      ),
    );
  }

  /// 按悬停进度 [t]（0~1）绘制导航项
  Widget _buildTile(AppPalette p, bool sel, double t) {
    // 背景：未选中时悬停“浮起”为面板色，并带细边框与轻投影；选中时保持强调浅底
    final bg = sel ? p.accentSoft : Color.lerp(p.panelRaised.withValues(alpha: 0), p.panelRaised, t)!;
    final border = sel ? Colors.transparent : p.borderStrong.withValues(alpha: t);
    // 竖条：选中时满高；未选中时悬停从 0 伸展到半高的半透明强调色
    final barMax = widget.height - 16;
    final barHeight = sel ? barMax : barMax * 0.5 * t;
    final barColor = sel ? p.accent : p.accent.withValues(alpha: 0.55 * t);
    final iconColor = sel ? p.accent : Color.lerp(p.textMuted, p.text, t)!;
    final fg = sel ? p.accent : p.text;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.radius),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: sel ? 0 : 0.08 * t),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 选中 / 悬停竖条
          Container(
            width: 3,
            height: barHeight,
            decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2)),
          ),
          // 悬停时内容向右滑动 3 像素
          SizedBox(width: 13 + 3 * t),
          Icon(widget.icon, size: 19, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: fg, fontWeight: sel ? FontWeight.w600 : FontWeight.w500),
            ),
          ),
          if (widget.trailing != null) ...[
            DefaultTextStyle.merge(
              style: TextStyle(fontSize: 12, color: p.textMuted),
              child: widget.trailing!,
            ),
            const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }
}

/// 二级导航栏：固定宽度的竖直导航（主机分组、设置分区），带可选标题与右侧动作
class SubNav extends StatelessWidget {
  const SubNav({super.key, this.title, this.titleAction, required this.children});

  final String? title;
  final Widget? titleAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: AppSizes.subNavWidth,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 6),
              child: SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title!,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.textMuted),
                      ),
                    ),
                    ?titleAction,
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 14),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
              children: [for (final c in children) Padding(padding: const EdgeInsets.only(bottom: 4), child: c)],
            ),
          ),
        ],
      ),
    );
  }
}
