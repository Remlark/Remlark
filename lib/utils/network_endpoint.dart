/// 用于临时连接测试的主机/端口，不接受 URL、路径或认证信息。
class NetworkEndpoint {
  const NetworkEndpoint(this.host, this.port);
  final String host;
  final int port;

  /// 解析 hostname:port、IPv4:port 或 [IPv6]:port。
  static NetworkEndpoint? tryParse(String input) {
    final value = input.trim();
    if (value.isEmpty || RegExp(r'\s|://').hasMatch(value)) return null;
    try {
      final uri = Uri.parse('tcp://$value');
      if (uri.host.isEmpty ||
          !uri.hasPort ||
          uri.userInfo.isNotEmpty ||
          uri.path.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.port < 1 ||
          uri.port > 65535) {
        return null;
      }
      final host = uri.host;
      return NetworkEndpoint(
        host.startsWith('[') && host.endsWith(']')
            ? host.substring(1, host.length - 1)
            : host,
        uri.port,
      );
    } on FormatException {
      return null;
    }
  }
}
