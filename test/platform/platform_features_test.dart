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

  test('RDP 扫描码：三种修饰键映射方式', () {
    const k = PhysicalKeyboardKey.metaLeft;
    const kr = PhysicalKeyboardKey.metaRight;
    const c = PhysicalKeyboardKey.controlLeft;
    const cr = PhysicalKeyboardKey.controlRight;
    // 不映射：Ctrl 为 Ctrl，Command / Win 为 Win
    expect(RdpScancode.fromKey(k), RdpScancode.winLeft);
    expect(RdpScancode.fromKey(kr), 0x100 | 0x5C);
    expect(RdpScancode.fromKey(c), RdpScancode.ctrlLeft);
    // Command 映射为 Ctrl，Ctrl 保持 Ctrl
    const m = RdpModifierMap.metaAsCtrl;
    expect(RdpScancode.fromKey(k, map: m), RdpScancode.ctrlLeft);
    expect(RdpScancode.fromKey(kr, map: m), 0x100 | 0x1D);
    expect(RdpScancode.fromKey(c, map: m), RdpScancode.ctrlLeft);
    // Ctrl 与 Win 互换
    const s = RdpModifierMap.swapCtrlMeta;
    expect(RdpScancode.fromKey(c, map: s), RdpScancode.winLeft);
    expect(RdpScancode.fromKey(cr, map: s), 0x100 | 0x5C);
    expect(RdpScancode.fromKey(k, map: s), RdpScancode.ctrlLeft);
    expect(RdpScancode.fromKey(kr, map: s), 0x100 | 0x1D);
    // 其他按键不受影响
    for (final map in RdpModifierMap.values) {
      expect(RdpScancode.fromKey(PhysicalKeyboardKey.keyV, map: map), RdpScancode.keyV);
      expect(RdpScancode.fromKey(PhysicalKeyboardKey.altLeft, map: map), RdpScancode.altLeft);
    }
  });

  test('RDP 修饰键映射按本机与远程系统决定，复制粘贴均用本机习惯', () {
    RdpModifierMap map(bool mac, String? os) => RdpScancode.modifierMap(localIsMac: mac, remoteOsId: os);
    // 本机 macOS：远程 Windows / Linux / 未知系统时 ⌘ 映射为 Ctrl；远程 macOS 不映射（⌘ 以 Win 键发出，即远程 Command）
    expect(map(true, 'windows'), RdpModifierMap.metaAsCtrl);
    expect(map(true, 'ubuntu'), RdpModifierMap.metaAsCtrl);
    expect(map(true, null), RdpModifierMap.metaAsCtrl);
    expect(map(true, 'macos'), RdpModifierMap.none);
    // 本机 Windows / Linux：远程 macOS 时 Ctrl 与 Win 互换（Ctrl+C 为远程 ⌘C），其余不映射
    expect(map(false, 'windows'), RdpModifierMap.none);
    expect(map(false, 'ubuntu'), RdpModifierMap.none);
    expect(map(false, null), RdpModifierMap.none);
    expect(map(false, 'macos'), RdpModifierMap.swapCtrlMeta);
    // 拖放上传后的自动粘贴使用远程系统的修饰键
    expect(RdpScancode.pasteModifier('macos'), RdpScancode.winLeft);
    expect(RdpScancode.pasteModifier('windows'), RdpScancode.ctrlLeft);
    expect(RdpScancode.pasteModifier(null), RdpScancode.ctrlLeft);
  });
}
