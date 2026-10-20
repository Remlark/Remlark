import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../../ssh/ssh_exec.dart';

/// 经 SSH 查询远程 macOS 的系统状态（如是否锁屏）
class RemoteMacState {
  RemoteMacState._();

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
