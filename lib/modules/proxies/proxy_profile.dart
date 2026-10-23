import '../hosts/host_model.dart';

/// 代理的本地身份、显示名称与连接参数。
class ProxyEntry {
  const ProxyEntry({
    required this.uuid,
    required this.name,
    required this.config,
  });

  final String uuid;
  final String name;
  final ProxyConfig config;

  /// 用户可读的协议名。
  String get protocolLabel => config.type == ProxyType.http ? 'HTTP' : 'SOCKS5';

  /// 地址中包含 IPv6 冒号时添加方括号。
  String get endpoint =>
      '${config.host.contains(':') ? '[${config.host}]' : config.host}:${config.port}';
}
