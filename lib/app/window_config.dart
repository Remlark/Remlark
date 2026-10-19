import 'dart:ui';

/// 窗口尺寸约定（逻辑像素）。各平台原生窗口代码使用相同数值：
/// macOS: macos/Runner/MainFlutterWindow.swift
/// Linux: linux/runner/my_application.cc
/// Windows: windows/runner/main.cpp 与 windows/runner/flutter_window.cpp
/// 修改时需同步修改上述文件；界面布局保证在最小尺寸下不溢出（见 test/layout_overflow_test.dart）
const Size kMinWindowSize = Size(960, 640);

/// 首次启动的默认窗口尺寸
const Size kDefaultWindowSize = Size(1280, 820);
