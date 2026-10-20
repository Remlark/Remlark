import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';

/// 表格列定义：固定宽度或按比例伸缩
class AppColumn {
  const AppColumn(this.label, {this.width, this.flex = 1, this.alignEnd = false});

  final String label;

  /// 固定宽度；为空时按 [flex] 伸缩
  final double? width;
  final int flex;

  /// 右对齐（数字列）
  final bool alignEnd;
}

/// 按列定义排布一行单元格
class AppTableCells extends StatelessWidget {
  const AppTableCells({super.key, required this.columns, required this.cells});

  final List<AppColumn> columns;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < columns.length; i++)
          _wrap(
            columns[i],
            Align(alignment: columns[i].alignEnd ? Alignment.centerRight : Alignment.centerLeft, child: cells[i]),
          ),
      ],
    );
  }

  Widget _wrap(AppColumn c, Widget child) {
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child);
    return c.width != null ? SizedBox(width: c.width, child: padded) : Expanded(flex: c.flex, child: padded);
  }
}

/// 表头：弱化文字 + 底部分隔线
class AppTableHeader extends StatelessWidget {
  const AppTableHeader({super.key, required this.columns, this.height = 40, this.padding = 12, this.trailing});

  final List<AppColumn> columns;
  final double height;
  final double padding;

  /// 列标题后的附加组件（排序箭头等），按列序号
  final Map<int, Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(fontSize: 13, color: p.textMuted, fontWeight: FontWeight.w500);
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: padding),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: AppTableCells(
        columns: columns,
        cells: [
          for (var i = 0; i < columns.length; i++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(columns[i].label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (trailing?[i] != null) trailing![i]!,
              ],
            ),
        ],
      ),
    );
  }
}

/// 表格行：悬停高亮、选中时强调色浅底与左侧竖条
class AppTableRow extends StatefulWidget {
  const AppTableRow({
    super.key,
    required this.columns,
    required this.cells,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapUp,
    this.height = 48,
    this.padding = 12,
    this.divider = true,
  });

  final List<AppColumn> columns;
  final List<Widget> cells;
  final bool selected;
  final GestureTapCallback? onTap;
  final GestureTapCallback? onDoubleTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final double height;
  final double padding;
  final bool divider;

  @override
  State<AppTableRow> createState() => _AppTableRowState();
}

class _AppTableRowState extends State<AppTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: widget.selected ? p.accentSoft : (_hover ? p.hover : null),
            border: Border(
              left: BorderSide(color: widget.selected ? p.accent : Colors.transparent, width: 3),
              bottom: widget.divider ? BorderSide(color: p.border.withValues(alpha: 0.6)) : BorderSide.none,
            ),
          ),
          padding: EdgeInsets.only(left: widget.padding - 3, right: widget.padding),
          child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 14, color: p.text),
            child: AppTableCells(columns: widget.columns, cells: widget.cells),
          ),
        ),
      ),
    );
  }
}
