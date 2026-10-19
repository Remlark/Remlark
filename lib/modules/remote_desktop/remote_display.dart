import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// 远程画面接口：VNC 与 RDP 会话都实现它，由通用的 RemoteScreen 组件负责渲染与输入转发
abstract class RemoteDisplay implements Listenable {
  /// 是否已有可显示的画面
  bool get displayReady;

  /// 读取当前画面（BGRA，行距 = 宽 * 4），无画面返回 null
  Uint8List? readFrame();

  /// 画面宽高
  int get frameWidth;
  int get frameHeight;

  /// 鼠标位置与按键（buttons：1 左键、2 中键、4 右键）
  void pointerEvent(int x, int y, int buttons);

  /// 滚轮（dy < 0 向上）
  void scrollEvent(int x, int y, double dy);

  /// 键盘事件
  KeyEventResult keyEvent(KeyEvent event);

  /// 画面获得焦点（用于同步剪贴板等）
  void displayFocused() {}

  /// 显示区域尺寸变化（逻辑像素），RDP 用于动态调整远程分辨率
  void viewResized(int width, int height) {}
}
