import 'package:flutter/services.dart';

/// Flutter 按键到 X11 keysym 的映射（VNC 键盘事件使用）
class VncKeysym {
  VncKeysym._();

  static final Map<LogicalKeyboardKey, int> _special = {
    LogicalKeyboardKey.backspace: 0xff08,
    LogicalKeyboardKey.tab: 0xff09,
    LogicalKeyboardKey.enter: 0xff0d,
    LogicalKeyboardKey.numpadEnter: 0xff8d,
    LogicalKeyboardKey.escape: 0xff1b,
    LogicalKeyboardKey.insert: 0xff63,
    LogicalKeyboardKey.delete: 0xffff,
    LogicalKeyboardKey.home: 0xff50,
    LogicalKeyboardKey.end: 0xff57,
    LogicalKeyboardKey.pageUp: 0xff55,
    LogicalKeyboardKey.pageDown: 0xff56,
    LogicalKeyboardKey.arrowLeft: 0xff51,
    LogicalKeyboardKey.arrowUp: 0xff52,
    LogicalKeyboardKey.arrowRight: 0xff53,
    LogicalKeyboardKey.arrowDown: 0xff54,
    LogicalKeyboardKey.f1: 0xffbe,
    LogicalKeyboardKey.f2: 0xffbf,
    LogicalKeyboardKey.f3: 0xffc0,
    LogicalKeyboardKey.f4: 0xffc1,
    LogicalKeyboardKey.f5: 0xffc2,
    LogicalKeyboardKey.f6: 0xffc3,
    LogicalKeyboardKey.f7: 0xffc4,
    LogicalKeyboardKey.f8: 0xffc5,
    LogicalKeyboardKey.f9: 0xffc6,
    LogicalKeyboardKey.f10: 0xffc7,
    LogicalKeyboardKey.f11: 0xffc8,
    LogicalKeyboardKey.f12: 0xffc9,
    LogicalKeyboardKey.shiftLeft: 0xffe1,
    LogicalKeyboardKey.shiftRight: 0xffe2,
    LogicalKeyboardKey.controlLeft: 0xffe3,
    LogicalKeyboardKey.controlRight: 0xffe4,
    LogicalKeyboardKey.capsLock: 0xffe5,
    LogicalKeyboardKey.metaLeft: 0xffeb,
    LogicalKeyboardKey.metaRight: 0xffec,
    LogicalKeyboardKey.altLeft: 0xffe9,
    LogicalKeyboardKey.altRight: 0xffea,
    LogicalKeyboardKey.space: 0x0020,
    LogicalKeyboardKey.printScreen: 0xff61,
    LogicalKeyboardKey.scrollLock: 0xff14,
    LogicalKeyboardKey.pause: 0xff13,
    LogicalKeyboardKey.numLock: 0xff7f,
    LogicalKeyboardKey.contextMenu: 0xff67,
  };

  /// 计算按键对应的 keysym，无法映射返回 null
  static int? fromEvent(KeyEvent event) {
    final special = _special[event.logicalKey];
    if (special != null) return special;
    final ch = event.character;
    if (ch != null && ch.isNotEmpty) {
      final code = ch.runes.first;
      if (code < 0x20) {
        // Ctrl 组合键产生的控制字符，使用按键标签字符
        return _fromLabel(event.logicalKey);
      }
      return code < 0x100 ? code : 0x01000000 + code;
    }
    return _fromLabel(event.logicalKey);
  }

  /// 从按键标签推导（字母键在 Ctrl 组合时 character 为空）
  static int? _fromLabel(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.length == 1) {
      return label.toLowerCase().codeUnitAt(0);
    }
    return null;
  }

  /// Ctrl+Alt+Del 序列
  static const ctrlAltDel = [0xffe3, 0xffe9, 0xffff];
}
