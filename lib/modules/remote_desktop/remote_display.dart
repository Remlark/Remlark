import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'frame_update.dart';

export 'frame_update.dart';

/// 远程鼠标指针图像（BGRA，带透明度）与热点；由本地按鼠标位置绘制
class RemoteCursor {
  const RemoteCursor({
    required this.width,
    required this.height,
    required this.hotX,
    required this.hotY,
    required this.bgra,
  });

  final int width;
  final int height;

  /// 热点（指针“尖端”在图像内的位置）
  final int hotX;
  final int hotY;
  final Uint8List bgra;
}

/// 远程画面接口：VNC 与 RDP 会话都实现它，由通用的 RemoteScreen 组件负责渲染与输入转发
abstract class RemoteDisplay implements Listenable {
  /// 是否已有可显示的画面
  bool get displayReady;

  /// 取出自上次调用以来的画面更新（整屏或若干完整的变化区域），没有新内容返回 null。
  /// 返回的总是完整的更新（不会是接收到一半的画面），按顺序覆盖到上一帧即为当前画面
  FrameUpdate? takeFrame();

  /// 画面宽高
  int get frameWidth;
  int get frameHeight;

  /// 远程指针图像；null 表示由系统指针显示（远程未提供指针形状）
  RemoteCursor? get cursor;

  /// 鼠标位置与按键（buttons：1 左键、2 中键、4 右键）
  void pointerEvent(int x, int y, int buttons);

  /// 滚轮：[steps] 为格数，负数向上、正数向下
  void scrollEvent(int x, int y, int steps);

  /// 键盘事件
  KeyEventResult keyEvent(KeyEvent event);

  /// 画面获得焦点（用于同步剪贴板等）
  void displayFocused() {}

  /// 画面失去焦点或本应用失去激活（如 ⌘+Tab 切走）：释放所有已按下的键与鼠标键。
  /// 否则按键的抬起事件被其他应用收到，远程会一直认为该键按着（如 ⌘ 卡住导致点击无法激活窗口）
  void displayBlurred() {}

  /// 显示区域尺寸变化（逻辑像素），RDP 用于动态调整远程分辨率
  void viewResized(int width, int height) {}
}
