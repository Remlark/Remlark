import 'dart:io';

import 'connect_error_policy_linux.dart';
import 'connect_error_policy_macos.dart';
import 'connect_error_policy_windows.dart';

/// 隔离系统 Socket 错误码，避免同一数值在不同平台含义不同。
abstract interface class ConnectErrorPolicy {
  /// 选择当前桌面平台的网络不可达判断实现。
  static ConnectErrorPolicy current() {
    if (Platform.isMacOS) return const MacosConnectErrorPolicy();
    if (Platform.isWindows) return const WindowsConnectErrorPolicy();
    if (Platform.isLinux) return const LinuxConnectErrorPolicy();
    return const UnsupportedConnectErrorPolicy();
  }

  /// 只判断可能暂时恢复的网络/主机不可达，不重试拒绝连接、权限或认证错误。
  bool isUnreachable(SocketException error);
}

/// 未支持的平台不猜测错误码。
class UnsupportedConnectErrorPolicy implements ConnectErrorPolicy {
  const UnsupportedConnectErrorPolicy();

  /// 未知系统立即返回原错误。
  @override
  bool isUnreachable(SocketException error) => false;
}
