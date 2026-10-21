import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/rdp/rdp_scancode.dart';
import 'package:remlark/modules/remote_desktop/vnc/lazy_file_clipboard.dart';
import 'package:remlark/modules/snippets/actions/install_system_key_action.dart';

/// 多平台测试 P-05：只在部分平台提供的功能与按平台区分的按键映射（见 docs/multi-platform-testing.md）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('VNC 延迟文件剪贴板：仅 macOS 支持，其余平台回退为复制时立即下载', () {
    expect(LazyFileClipboard.instance.supported, Platform.isMacOS);
  });

  test('系统免密登录快捷指令：仅 macOS / Linux 可用', () {
    expect(InstallSystemKeyAction().isAvailable, !Platform.isWindows);
  });

  test('RDP 扫描码：macOS 习惯下 Command 映射为 Ctrl，Windows / Linux 保持 Win 键', () {
    // 左右 Command / Win 键
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.metaLeft, metaAsCtrl: true), RdpScancode.ctrlLeft);
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.metaRight, metaAsCtrl: true), 0x100 | 0x1D);
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.metaLeft), RdpScancode.winLeft);
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.metaRight), 0x100 | 0x5C);
    // 其他按键不受影响
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.keyV, metaAsCtrl: true), RdpScancode.keyV);
    expect(RdpScancode.fromKey(PhysicalKeyboardKey.controlLeft), RdpScancode.ctrlLeft);
  });
}
