import 'dart:io';

import 'connect_error_policy.dart';

/// Linux 的 ENETUNREACH / EHOSTUNREACH（Windows 对应 WSA 错误码）。
class LinuxConnectErrorPolicy implements ConnectErrorPolicy {
  const LinuxConnectErrorPolicy();

  /// 通过本平台原生错误码判断，避免依赖操作系统语言和错误文案。
  @override
  bool isUnreachable(SocketException error) => error.osError?.errorCode == 101 || error.osError?.errorCode == 113;
}
