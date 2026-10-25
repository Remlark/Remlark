import 'package:xterm/xterm.dart';

/// 修正 xterm 4.x 在宽度变化时 reflow 后光标行不跟随的问题。
///
/// xterm 的 Buffer.resize 在 reflow（长行折行 / 合并）后不会调整 cursorY，
/// 多次调整窗口或侧栏宽度后光标会逐渐“漂”到内容下方，
/// 导致新提示符出现在屏幕中间、上方留下大片空白。
/// 这里在 resize 前于光标所在行首放置锚点，resize 后按锚点的新位置还原光标。
class ReflowSafeTerminal extends Terminal {
  ReflowSafeTerminal({super.maxLines});

  /// xterm 4.x 将 SGR 22 只映射到此方法；正常字重应同时关闭粗体和淡化。
  @override
  void unsetCursorFaint() {
    super.unsetCursorFaint();
    super.unsetCursorBold();
  }

  /// 调整终端尺寸，并按锚点修正主缓冲区的光标位置
  @override
  void resize(int newWidth, int newHeight, [int? pixelWidth, int? pixelHeight]) {
    final buf = mainBuffer;
    final widthChanged = newWidth != viewWidth;
    // 只有宽度变化且启用 reflow 时才会出现漂移；锚点放在行首，保证 reflow 拷贝内容时会被迁移
    final anchor = widthChanged && reflowEnabled ? buf.createAnchor(0, buf.absoluteCursorY) : null;
    final cursorX = buf.cursorX;
    super.resize(newWidth, newHeight, pixelWidth, pixelHeight);
    if (anchor == null) return;
    if (anchor.attached) {
      // 光标在逻辑行内的偏移 = 原行首在新行中的偏移 + 原光标列，超出宽度的部分折到后续行
      final logicalX = anchor.x + cursorX;
      final absY = (anchor.y + logicalX ~/ viewWidth).clamp(0, buf.lines.length - 1);
      buf.setCursorY(absY - buf.scrollBack);
      buf.setCursorX(logicalX % viewWidth);
    }
    anchor.dispose();
  }
}
