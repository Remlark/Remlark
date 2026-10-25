/// FreeRDP 3.x 连接错误码，三平台共用协议层分类，不依赖系统错误文案。
/// 对应 include/freerdp/error.h 中 CONNECT 类（2 << 16）。
class RdpConnectError implements Exception {
  const RdpConnectError(this.code, this.message);

  final int code;
  final String message;

  /// 仅重试 DNS 临时错误、TCP 建连失败和传输失败。
  /// 域名不存在、认证、权限、TLS/证书和用户取消交给原有流程处理。
  bool get retryable =>
      code == 0x00020004 || code == 0x00020006 || code == 0x0002000d;

  /// 保留原生错误描述，供最终失败界面与日志使用。
  @override
  String toString() => message;
}
