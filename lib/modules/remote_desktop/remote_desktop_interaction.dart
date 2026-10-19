import '../hosts/host_model.dart';
import '../ssh/ssh_interaction.dart';

/// 远程桌面（VNC / RDP）连接过程中需要用户参与的交互，由 UI 层实现
abstract class RemoteDesktopInteraction {
  /// 请求输入远程桌面密码；[error] 非空表示上一次密码错误
  Future<PasswordInput?> askDesktopPassword(HostEntry host, {String? error});

  /// 服务器证书指纹与记录不一致时确认是否继续
  Future<bool> confirmCertificateChanged(HostEntry host, String oldFingerprint, String newFingerprint);
}
