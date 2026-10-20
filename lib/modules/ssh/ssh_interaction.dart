import 'package:dartssh2/dartssh2.dart';

import '../hosts/host_model.dart';

/// 密码输入结果
class PasswordInput {
  const PasswordInput(this.password, {this.remember = false, this.username});

  final String password;

  /// 用户名（仅在对话框同时询问用户名时有值，如 macOS 屏幕共享）
  final String? username;

  /// 是否勾选“记住密码”
  final bool remember;
}

/// SSH 连接过程中需要用户参与的交互接口（由 UI 层实现），
/// 与连接逻辑解耦，便于测试与替换
abstract class SshInteraction {
  /// 请求输入密码。[error] 非空表示上一次密码错误
  Future<PasswordInput?> askPassword(HostEntry host, {String? error});

  /// 请求输入私钥口令
  Future<String?> askPassphrase(HostEntry host, {String? error});

  /// 主机指纹与记录不一致时确认是否继续
  Future<bool> confirmHostKeyChanged(HostEntry host, String keyType, String oldFingerprint, String newFingerprint);

  /// keyboard-interactive 认证提示
  Future<List<String>?> keyboardInteractive(HostEntry host, SSHUserInfoRequest request);

  /// 连接进度提示（例如“正在通过跳板 xxx 连接”）
  void onProgress(String message) {}
}

/// 用户取消连接
class ConnectCancelled implements Exception {
  @override
  String toString() => 'cancelled';
}
