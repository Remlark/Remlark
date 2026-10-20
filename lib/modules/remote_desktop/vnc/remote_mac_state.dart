import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../../../utils/app_log.dart';
import '../../ssh/ssh_exec.dart';

/// 经 SSH 查询远程 macOS 的系统状态（用于诊断，如修饰键是否卡住）
class RemoteMacState {
  RemoteMacState._();

  /// 修饰键标志位（CGEventFlags）
  static const _flags = {0x10000: '大写锁定', 0x20000: '⇧', 0x40000: '⌃', 0x80000: '⌥', 0x100000: '⌘'};

  /// 读取远程修饰键状态（合并会话状态与 HID 系统状态取并集）；失败返回 null
  static Future<int?> modifierFlags(SSHClient client) async {
    try {
      final r = await SshExec.run(
        client,
        "osascript -l JavaScript -e 'ObjC.import(\"CoreGraphics\"); "
        "[\$.CGEventSourceFlagsState(0), \$.CGEventSourceFlagsState(1)].join(\",\")'",
        timeout: const Duration(seconds: 8),
      );
      final parts = r.stdout.trim().split(',').map(int.tryParse).toList();
      if (parts.length != 2 || parts.contains(null)) return null;
      return parts[0]! | parts[1]!;
    } catch (_) {
      return null;
    }
  }

  /// 按下的修饰键名称列表
  static List<String> pressed(int flags) => [
    for (final e in _flags.entries)
      if (flags & e.key != 0) e.value,
  ];

  /// 查询并写日志，返回按下的修饰键（失败返回 null）
  static Future<List<String>?> logModifiers(SSHClient client, String when) async {
    final f = await modifierFlags(client);
    if (f == null) {
      AppLog.d('vnc.key', '$when：无法读取远程修饰键状态');
      return null;
    }
    final keys = pressed(f);
    if (keys.isEmpty) {
      AppLog.i('vnc.key', '$when：远程没有按下的修饰键');
    } else {
      AppLog.w('vnc.key', '$when：远程修饰键处于按下状态 $keys（flags=0x${f.toRadixString(16)}）');
    }
    return keys;
  }

  /// 远程控制台会话是否锁屏（读取 IOConsoleUsers 的 CGSSessionScreenIsLocked，无需授权）；失败返回 null
  static Future<bool?> screenLocked(SSHClient client) async {
    try {
      final r = await SshExec.run(
        client,
        'ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers json -o - -',
        timeout: const Duration(seconds: 8),
      );
      final list = jsonDecode(r.stdout.trim()) as List;
      for (final u in list.cast<Map<String, dynamic>>()) {
        if (u['kCGSSessionOnConsoleKey'] == true) return u['CGSSessionScreenIsLocked'] == true;
      }
      return false;
    } catch (_) {
      return null;
    }
  }
}
