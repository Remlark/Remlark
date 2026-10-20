import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme/app_palette.dart';
import '../app/theme/app_theme.dart';

/// 菜单条目（菜单项或分隔线）
sealed class AppMenuEntry<T> {
  const AppMenuEntry();
}

/// 菜单分隔线
class AppMenuDivider<T> extends AppMenuEntry<T> {
  const AppMenuDivider();
}

/// 菜单项：选中后菜单关闭，返回 [value] 并调用 [onTap]
class AppMenuItem<T> extends AppMenuEntry<T> {
  const AppMenuItem({
    this.value,
    required this.label,
    this.icon,
    this.iconColor,
    this.description,
    this.shortcut,
    this.danger = false,
    this.enabled = true,
    this.onTap,
  });

  final T? value;
  final String label;
  final IconData? icon;

  /// 图标颜色（默认次要文字色，危险项为危险色）
  final Color? iconColor;

  /// 标题下方的说明文字（可换行）
  final String? description;

  /// 右侧快捷键提示
  final String? shortcut;

  /// 危险操作（删除等）以危险色显示
  final bool danger;
  final bool enabled;

  /// 选中后的回调（菜单关闭后执行）
  final VoidCallback? onTap;
}

/// 统一的弹出菜单：右键菜单与下拉菜单共用。
/// - 无打开 / 关闭动画，立即显示；
/// - 下拉菜单左边与触发控件对齐，显示在其下方（下方放不下时显示在上方），宽度不小于触发控件；
/// - 右键菜单显示在鼠标位置，超出屏幕时向左 / 向上翻转；
/// - 点击菜单外任意位置（含右键）或按 Esc 关闭，方向键切换菜单项，回车选中
class AppMenu {
  AppMenu._();

  /// 菜单与屏幕边缘的最小距离
  static const _screenMargin = 8.0;

  /// 下拉菜单与触发控件的间距
  static const _gap = 4.0;

  /// 右键菜单的最小宽度
  static const _contextMinWidth = 180.0;

  /// 在全局坐标 [position] 处弹出右键菜单，返回选中项的值（取消为 null）
  static Future<T?> showAt<T>(
    BuildContext context,
    Offset position,
    List<AppMenuEntry<T>> items, {
    double? minWidth,
    double? maxWidth,
  }) => _show(
    context,
    anchor: Rect.fromLTWH(position.dx, position.dy, 0, 0),
    below: false,
    items: items,
    minWidth: minWidth ?? _contextMinWidth,
    maxWidth: maxWidth,
  );

  /// 在 [anchorContext] 对应控件的下方弹出下拉菜单，返回选中项的值（取消为 null）。
  /// [matchWidth] 为 true 时菜单与控件等宽（选择框），否则宽度不小于控件、可按内容加宽（按钮）
  static Future<T?> showBelow<T>(
    BuildContext anchorContext,
    List<AppMenuEntry<T>> items, {
    T? selected,
    bool matchWidth = false,
    double? minWidth,
    double? maxWidth,
  }) {
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Future.value();
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return _show(
      anchorContext,
      anchor: rect,
      below: true,
      items: items,
      selected: selected,
      hasSelection: selected != null,
      minWidth: math.max(rect.width, minWidth ?? 0),
      maxWidth: matchWidth ? rect.width : maxWidth,
    );
  }

  static Future<T?> _show<T>(
    BuildContext context, {
    required Rect anchor,
    required bool below,
    required List<AppMenuEntry<T>> items,
    T? selected,
    bool hasSelection = false,
    double minWidth = 0,
    double? maxWidth,
  }) async {
    final nav = Navigator.of(context);
    final item = await nav.push(
      _AppMenuRoute<T>(
        anchor: anchor,
        below: below,
        items: items,
        selected: selected,
        hasSelection: hasSelection,
        minWidth: minWidth,
        maxWidth: maxWidth,
        // 带上触发处的主题等继承数据，保证菜单与触发控件外观一致
        capturedThemes: InheritedTheme.capture(from: context, to: nav.context),
        barrierLabel: MaterialLocalizations.of(context).menuDismissLabel,
      ),
    );
    item?.onTap?.call();
    return item?.value;
  }
}

/// 菜单路由：无过渡动画，透明全屏层接收菜单外的点击并关闭
class _AppMenuRoute<T> extends PopupRoute<AppMenuItem<T>> {
  _AppMenuRoute({
    required this.anchor,
    required this.below,
    required this.items,
    required this.selected,
    required this.hasSelection,
    required this.minWidth,
    required this.maxWidth,
    required this.capturedThemes,
    required this.barrierLabel,
  });

  final Rect anchor;
  final bool below;
  final List<AppMenuEntry<T>> items;
  final T? selected;
  final bool hasSelection;
  final double minWidth;
  final double? maxWidth;
  final CapturedThemes capturedThemes;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  bool get barrierDismissible => true;

  @override
  Color? get barrierColor => null;

  @override
  final String barrierLabel;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    return Stack(
      children: [
        // 菜单外任意按键（左键、右键、中键）都关闭菜单
        Positioned.fill(
          child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) => Navigator.of(context).maybePop()),
        ),
        CustomSingleChildLayout(
          delegate: _MenuLayout(
            anchor: anchor,
            below: below,
            minWidth: minWidth,
            maxWidth: maxWidth,
            padding: MediaQuery.paddingOf(context),
          ),
          child: capturedThemes.wrap(_MenuPanel<T>(items: items, selected: selected, hasSelection: hasSelection)),
        ),
      ],
    );
  }
}

/// 菜单定位：下拉菜单贴着触发控件，右键菜单在鼠标处；超出屏幕时翻转或贴边
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({
    required this.anchor,
    required this.below,
    required this.minWidth,
    required this.maxWidth,
    required this.padding,
  });

  final Rect anchor;
  final bool below;
  final double minWidth;
  final double? maxWidth;
  final EdgeInsets padding;

  static const _m = AppMenu._screenMargin;
  static const _gap = AppMenu._gap;

  /// 可用区域（去掉系统边距与屏幕留白）
  Rect _area(Size size) => Rect.fromLTRB(
    padding.left + _m,
    padding.top + _m,
    size.width - padding.right - _m,
    size.height - padding.bottom - _m,
  );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final area = _area(constraints.biggest);
    final maxW = math.min(maxWidth ?? area.width, area.width);
    final minW = math.min(minWidth, maxW);
    // 下拉菜单最高为上下两侧中较大的空间
    final maxH = below ? math.max(area.bottom - anchor.bottom - _gap, anchor.top - _gap - area.top) : area.height;
    return BoxConstraints(minWidth: minW, maxWidth: maxW, maxHeight: math.max(maxH, 0));
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final area = _area(size);
    double x;
    double y;
    if (below) {
      // 左对齐触发控件，右侧放不下时整体左移
      x = anchor.left;
      final belowY = anchor.bottom + _gap;
      final aboveY = anchor.top - _gap - child.height;
      if (belowY + child.height <= area.bottom) {
        y = belowY;
      } else if (aboveY >= area.top) {
        y = aboveY;
      } else {
        // 两侧都放不下：用空间更大的一侧（高度已在约束中限制）
        y = area.bottom - anchor.bottom >= anchor.top - area.top ? belowY : aboveY;
      }
    } else {
      // 鼠标位置；右 / 下放不下时向左 / 向上翻转
      x = anchor.left + child.width <= area.right ? anchor.left : anchor.left - child.width;
      y = anchor.top + child.height <= area.bottom ? anchor.top : anchor.top - child.height;
    }
    x = x.clamp(area.left, math.max(area.left, area.right - child.width));
    y = y.clamp(area.top, math.max(area.top, area.bottom - child.height));
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) =>
      anchor != old.anchor ||
      below != old.below ||
      minWidth != old.minWidth ||
      maxWidth != old.maxWidth ||
      padding != old.padding;
}

/// 菜单面板：圆角描边浮层，内容过多时滚动
class _MenuPanel<T> extends StatelessWidget {
  const _MenuPanel({required this.items, required this.selected, required this.hasSelection});

  final List<AppMenuEntry<T>> items;
  final T? selected;
  final bool hasSelection;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // 下拉选择时焦点落在当前选中项，方便键盘切换
    final focusIndex = hasSelection ? items.indexWhere((e) => e is AppMenuItem<T> && e.value == selected) : -1;
    return Shortcuts(
      // 方向键在菜单项之间移动焦点
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
      },
      child: Material(
        color: p.panelRaised,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          side: BorderSide(color: p.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, e) in items.indexed)
                  switch (e) {
                    AppMenuDivider<T>() => Divider(height: 9, thickness: 1, color: p.border),
                    AppMenuItem<T>() => _MenuItemTile<T>(
                      item: e,
                      selected: hasSelection && e.value == selected,
                      autofocus: i == focusIndex,
                    ),
                  },
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个菜单项：图标 + 标题（+ 说明）+ 快捷键 / 选中勾
class _MenuItemTile<T> extends StatelessWidget {
  const _MenuItemTile({required this.item, required this.selected, required this.autofocus});

  final AppMenuItem<T> item;
  final bool selected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = item;
    final fg = !e.enabled
        ? p.textFaint
        : e.danger
        ? p.danger
        : selected
        ? p.accent
        : p.text;
    final iconColor = !e.enabled ? p.textFaint : (e.danger ? p.danger : (e.iconColor ?? p.textMuted));
    return InkWell(
      autofocus: autofocus,
      onTap: e.enabled ? () => Navigator.of(context).pop(e) : null,
      hoverColor: p.hover,
      focusColor: p.hover,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: e.description == null ? 8 : 9),
          child: Row(
            crossAxisAlignment: e.description == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              if (e.icon != null) ...[
                Padding(
                  padding: EdgeInsets.only(top: e.description == null ? 0 : 1),
                  child: Icon(e.icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      e.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: fg,
                        fontWeight: e.description == null ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                    if (e.description != null) ...[
                      const SizedBox(height: 2),
                      Text(e.description!, style: TextStyle(fontSize: 12, color: p.textMuted)),
                    ],
                  ],
                ),
              ),
              if (e.shortcut != null) ...[
                const SizedBox(width: 24),
                Text(e.shortcut!, style: TextStyle(fontSize: 12, color: p.textFaint)),
              ],
              if (selected) ...[const SizedBox(width: 10), Icon(Icons.check_rounded, size: 18, color: p.accent)],
            ],
          ),
        ),
      ),
    );
  }
}

/// 下拉菜单触发器：包裹任意按钮，调用 builder 中的 open 即在按钮下方弹出菜单。
/// 菜单左边与按钮对齐，宽度不小于按钮
class AppMenuAnchor<T> extends StatelessWidget {
  const AppMenuAnchor({
    super.key,
    required this.builder,
    required this.items,
    this.onSelected,
    this.selected,
    this.minWidth,
    this.maxWidth,
  });

  /// 构建触发按钮；按钮点击时调用 open
  final Widget Function(BuildContext context, VoidCallback open) builder;

  /// 菜单条目（打开时调用，保证内容是最新的）
  final List<AppMenuEntry<T>> Function(BuildContext context) items;
  final ValueChanged<T>? onSelected;

  /// 当前选中值（显示勾选）
  final T? selected;
  final double? minWidth;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchorContext) => builder(anchorContext, () async {
        final v = await AppMenu.showBelow<T>(
          anchorContext,
          items(anchorContext),
          selected: selected,
          minWidth: minWidth,
          maxWidth: maxWidth,
        );
        if (v != null) onSelected?.call(v);
      }),
    );
  }
}

/// 下拉选择框：替代 DropdownButtonFormField / DropdownButton。
/// 外观与输入框一致（[borderless] 为无边框紧凑样式），菜单与选择框等宽，当前值打勾
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.borderless = false,
  });

  final T? value;
  final List<AppMenuItem<T>> items;

  /// 为 null 时禁用
  final ValueChanged<T?>? onChanged;

  /// 无选中值时的提示
  final String? hint;

  /// 无边框样式（如聊天面板顶部的 Agent 选择）
  final bool borderless;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final _focus = FocusNode();
  bool _open = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// 当前选中项（值不在列表中时为 null）
  AppMenuItem<T>? get _current => widget.items.where((e) => e.value == widget.value).firstOrNull;

  Future<void> _show() async {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    setState(() => _open = true);
    // 用自定义返回值区分“选中值为 null 的项”与“取消”
    final picked = await AppMenu.showBelow<_Picked<T>>(
      context,
      [
        for (final e in widget.items)
          AppMenuItem(
            value: _Picked(e.value),
            label: e.label,
            icon: e.icon,
            iconColor: e.iconColor,
            description: e.description,
            enabled: e.enabled,
          ),
      ],
      selected: _current == null ? null : _Picked(widget.value),
      matchWidth: true,
    );
    if (!mounted) return;
    setState(() => _open = false);
    _focus.requestFocus();
    if (picked != null && picked.value != widget.value) onChanged(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onChanged != null;
    final cur = _current;
    final text = cur?.label ?? widget.hint ?? '';
    final color = !enabled ? p.textFaint : (cur == null ? p.textFaint : p.text);
    final content = Row(
      children: [
        if (cur?.icon != null) ...[
          Icon(cur!.icon, size: 16, color: cur.iconColor ?? p.textMuted),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: color),
          ),
        ),
        Icon(Icons.arrow_drop_down_rounded, size: 22, color: enabled ? p.textMuted : p.textFaint),
      ],
    );
    return InkWell(
      focusNode: _focus,
      onTap: enabled ? _show : null,
      hoverColor: widget.borderless ? p.hover : Colors.transparent,
      focusColor: widget.borderless ? p.hover : Colors.transparent,
      borderRadius: BorderRadius.circular(AppSizes.radius),
      child: widget.borderless
          ? Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: content)
          : ListenableBuilder(
              listenable: _focus,
              // 与输入框相同的边框、底色与聚焦样式；菜单打开时显示聚焦边框
              builder: (context, _) => InputDecorator(
                decoration: InputDecoration(enabled: enabled, contentPadding: const EdgeInsets.fromLTRB(12, 10, 6, 10)),
                isFocused: _open || _focus.hasFocus,
                child: content,
              ),
            ),
    );
  }
}

/// 下拉选择框内部的返回值包装（允许选中值为 null 的项）
class _Picked<T> {
  const _Picked(this.value);

  final T? value;

  @override
  bool operator ==(Object other) => other is _Picked<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
