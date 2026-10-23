/// 主机协议
enum HostProtocol {
  ssh(22),
  rdp(3389),
  vnc(5900);

  const HostProtocol(this.defaultPort);

  /// 协议默认端口
  final int defaultPort;

  /// 从字符串解析，未知值回退为 ssh
  static HostProtocol parse(String? v) => HostProtocol.values.firstWhere((e) => e.name == v, orElse: () => ssh);
}

/// SSH 认证方式
enum AuthType {
  password,
  key,
  keyboard;

  static AuthType parse(String? v) => AuthType.values.firstWhere((e) => e.name == v, orElse: () => password);
}

/// 出口代理类型
enum ProxyType {
  none,
  http,
  socks5;

  static ProxyType parse(String? v) => ProxyType.values.firstWhere((e) => e.name == v, orElse: () => none);
}

/// 出口代理配置
class ProxyConfig {
  const ProxyConfig({this.type = ProxyType.none, this.host = '', this.port = 0, this.username = '', this.password});

  final ProxyType type;
  final String host;
  final int port;
  final String username;
  final String? password;

  bool get enabled => type != ProxyType.none && host.isNotEmpty && port > 0;

  /// 比较完整连接配置，空密码和未设置密码具有相同语义。
  bool sameConnectionAs(ProxyConfig other) => type == other.type && host == other.host &&
      port == other.port && username == other.username && (password ?? '') == (other.password ?? '');

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'host': host,
    'port': port,
    'username': username,
    if (password != null) 'password': password,
  };

  factory ProxyConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const ProxyConfig();
    return ProxyConfig(
      type: ProxyType.parse(j['type'] as String?),
      host: j['host'] as String? ?? '',
      port: (j['port'] as num?)?.toInt() ?? 0,
      username: j['username'] as String? ?? '',
      password: j['password'] as String?,
    );
  }
}

/// 主机领域模型（敏感字段为解密后的明文，仅在内存中使用）
class HostEntry {
  HostEntry({
    required this.uuid,
    required this.protocol,
    required this.name,
    this.groupUuid,
    required this.address,
    required this.port,
    this.username = '',
    this.authType = AuthType.password,
    this.password,
    this.savePassword = false,
    this.keyUuid,
    this.jumpChain = const [],
    this.proxy = const ProxyConfig(),
    this.proxyUuid,
    this.osId,
    this.osName,
    this.hostKeyFingerprint,
    this.extra = const {},
    this.note = '',
    this.syncEnabled = false,
    this.syncedAt,
    required this.updatedAt,
    required this.createdAt,
    this.lastConnectedAt,
  });

  final String uuid;
  final HostProtocol protocol;
  final String name;
  final String? groupUuid;
  final String address;
  final int port;
  final String username;
  final AuthType authType;
  final String? password;
  final bool savePassword;
  final String? keyUuid;
  final List<String> jumpChain;
  final ProxyConfig proxy;

  /// 本地共享代理标识；可移植载荷使用连接快照，避免跨设备悬空引用。
  final String? proxyUuid;
  final String? osId;
  final String? osName;
  final String? hostKeyFingerprint;

  /// 协议相关的额外配置，例如 RDP 域、分辨率，VNC 关联 SSH 主机等
  final Map<String, dynamic> extra;
  final String note;
  final bool syncEnabled;
  final int? syncedAt;
  final int updatedAt;
  final int createdAt;
  final int? lastConnectedAt;

  /// 显示用的“用户@地址:端口”
  String get endpoint {
    final user = username.isEmpty ? '' : '$username@';
    final portPart = port == protocol.defaultPort ? '' : ':$port';
    return '$user$address$portPart';
  }

  /// 同步状态
  SyncState get syncState {
    if (!syncEnabled) return SyncState.local;
    if (syncedAt == null) return SyncState.pending;
    return syncedAt == updatedAt ? SyncState.synced : SyncState.pending;
  }

  HostEntry copyWith({
    String? uuid,
    HostProtocol? protocol,
    String? name,
    String? Function()? groupUuid,
    String? address,
    int? port,
    String? username,
    AuthType? authType,
    String? Function()? password,
    bool? savePassword,
    String? Function()? keyUuid,
    List<String>? jumpChain,
    ProxyConfig? proxy,
    String? Function()? proxyUuid,
    String? Function()? osId,
    String? Function()? osName,
    String? Function()? hostKeyFingerprint,
    Map<String, dynamic>? extra,
    String? note,
    bool? syncEnabled,
    int? Function()? syncedAt,
    int? updatedAt,
    int? createdAt,
    int? Function()? lastConnectedAt,
  }) {
    return HostEntry(
      uuid: uuid ?? this.uuid,
      protocol: protocol ?? this.protocol,
      name: name ?? this.name,
      groupUuid: groupUuid != null ? groupUuid() : this.groupUuid,
      address: address ?? this.address,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      password: password != null ? password() : this.password,
      savePassword: savePassword ?? this.savePassword,
      keyUuid: keyUuid != null ? keyUuid() : this.keyUuid,
      jumpChain: jumpChain ?? this.jumpChain,
      proxy: proxy ?? this.proxy,
      proxyUuid: proxyUuid != null ? proxyUuid() : this.proxyUuid,
      osId: osId != null ? osId() : this.osId,
      osName: osName != null ? osName() : this.osName,
      hostKeyFingerprint: hostKeyFingerprint != null ? hostKeyFingerprint() : this.hostKeyFingerprint,
      extra: extra ?? this.extra,
      note: note ?? this.note,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncedAt: syncedAt != null ? syncedAt() : this.syncedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt != null ? lastConnectedAt() : this.lastConnectedAt,
    );
  }

  /// 序列化为可移植 JSON（导出 / 同步载荷）。[withSecrets] 决定是否包含密码
  Map<String, dynamic> toPortableJson({bool withSecrets = true}) => {
    'uuid': uuid,
    'protocol': protocol.name,
    'name': name,
    'address': address,
    'port': port,
    'username': username,
    'authType': authType.name,
    'savePassword': savePassword && withSecrets,
    if (withSecrets && savePassword && password != null) 'password': password,
    if (keyUuid != null) 'keyUuid': keyUuid,
    'jumpChain': jumpChain,
    'proxy': withSecrets ? proxy.toJson() : (proxy.toJson()..remove('password')),
    if (osId != null) 'osId': osId,
    if (osName != null) 'osName': osName,
    'extra': extra,
    'note': note,
    'updatedAt': updatedAt,
    'createdAt': createdAt,
  };

  /// 从可移植 JSON 构造（分组由调用方另行处理）
  factory HostEntry.fromPortableJson(Map<String, dynamic> j) {
    final protocol = HostProtocol.parse(j['protocol'] as String?);
    final now = DateTime.now().millisecondsSinceEpoch;
    return HostEntry(
      uuid: j['uuid'] as String,
      protocol: protocol,
      name: j['name'] as String? ?? '',
      address: j['address'] as String? ?? '',
      port: (j['port'] as num?)?.toInt() ?? protocol.defaultPort,
      username: j['username'] as String? ?? '',
      authType: AuthType.parse(j['authType'] as String?),
      password: j['password'] as String?,
      savePassword: j['savePassword'] == true,
      keyUuid: j['keyUuid'] as String?,
      jumpChain: (j['jumpChain'] as List?)?.cast<String>() ?? const [],
      proxy: ProxyConfig.fromJson((j['proxy'] as Map?)?.cast<String, dynamic>()),
      osId: j['osId'] as String?,
      osName: j['osName'] as String?,
      extra: (j['extra'] as Map?)?.cast<String, dynamic>() ?? const {},
      note: j['note'] as String? ?? '',
      updatedAt: (j['updatedAt'] as num?)?.toInt() ?? now,
      createdAt: (j['createdAt'] as num?)?.toInt() ?? now,
    );
  }
}

/// 主机同步状态
enum SyncState {
  /// 未参与同步（仅本地）
  local,

  /// 参与同步，与服务器一致
  synced,

  /// 参与同步，但本地有未同步的修改
  pending,
}

/// 分组领域模型
class GroupEntry {
  const GroupEntry({required this.uuid, required this.name, this.sortOrder = 0});

  final String uuid;
  final String name;
  final int sortOrder;
}
