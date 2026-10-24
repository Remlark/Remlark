import 'host_model.dart';

/// 同一主机的 SSH 连接配置（独立终端及 VNC 文件传输、剪贴板共用）。
/// 地址、用户名、密码与 VNC 共用（macOS 屏幕共享的 VNC 登录即系统账户），只需补充端口与认证方式。
/// 保存在 VNC 主机 extra['ssh'] 中
class VncSshConfig {
  const VncSshConfig({
    this.enabled = false,
    this.port = 22,
    this.authType = AuthType.password,
    this.keyUuid,
  });

  /// 启用双协议时的便捷配置：22 端口、密码认证
  static const defaults = VncSshConfig(enabled: true);

  final bool enabled;
  final int port;

  /// 认证方式：password（与 VNC 共用密码）或 key
  final AuthType authType;
  final String? keyUuid;

  static const _key = 'ssh';

  /// 从主机 extra 读取；未配置返回 null
  static VncSshConfig? fromExtra(Map<String, dynamic> extra) {
    final m = extra[_key];
    if (m is! Map) return null;
    return VncSshConfig(
      enabled: m['enabled'] == true,
      port: (m['port'] as num?)?.toInt() ?? 22,
      authType: AuthType.parse(m['auth'] as String?),
      keyUuid: m['key'] as String?,
    );
  }

  /// 写入 extra
  void writeTo(Map<String, dynamic> extra) {
    extra[_key] = {
      'enabled': enabled,
      'port': port,
      'auth': authType.name,
      if (authType == AuthType.key && keyUuid != null) 'key': keyUuid,
    };
  }

  /// 生成修改后的内置 SSH 配置。
  VncSshConfig copyWith({
    bool? enabled,
    int? port,
    AuthType? authType,
    String? Function()? keyUuid,
  }) => VncSshConfig(
    enabled: enabled ?? this.enabled,
    port: port ?? this.port,
    authType: authType ?? this.authType,
    keyUuid: keyUuid != null ? keyUuid() : this.keyUuid,
  );
}

/// VNC 主机的 SSH 相关扩展
extension HostVncSsh on HostEntry {
  /// 主机拥有的连接协议，双协议主机在两个筛选分类中都可找到。
  List<HostProtocol> get connectionProtocols => [
    for (final p in HostProtocol.values)
      if (p == protocol ||
          connectionProfile(p) != null ||
          (p == HostProtocol.ssh && vncSsh != null))
        p,
  ];

  /// 读取同一主机上的附加连接参数。密码在仓库读写时单独加解密。
  Map<String, dynamic>? connectionProfile(HostProtocol requested) {
    final profiles = extra['connections'];
    if (profiles is! Map || profiles[requested.name] is! Map) return null;
    return Map<String, dynamic>.from(profiles[requested.name] as Map);
  }

  /// 生成指定协议的连接参数，沿用同一主机身份而不新增数据库记录。
  HostEntry forConnection(HostProtocol requested) {
    if (requested == protocol) return this;
    final profile = connectionProfile(requested);
    if (profile != null) {
      final decoded = HostEntry.fromPortableJson({
        ...profile,
        'uuid': uuid,
        'protocol': requested.name,
        'name': name,
        'address': address,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      });
      return decoded.copyWith(
        groupUuid: () => groupUuid,
        osId: () => osId,
        osName: () => osName,
        extra: {
          ...decoded.extra,
          if (extra['osOverride'] != null) 'osOverride': extra['osOverride'],
        },
        syncEnabled: syncEnabled,
        syncedAt: () => syncedAt,
        lastConnectedAt: () => lastConnectedAt,
        hostKeyFingerprint: () => profile['hostKeyFingerprint'] as String?,
      );
    }
    final ssh = vncSsh;
    if (requested == HostProtocol.ssh && ssh != null) return asSshHost(ssh);
    throw StateError('Host does not support ${requested.name}');
  }

  /// 已启用的内置 SSH 配置（非 VNC 主机或未启用返回 null）
  VncSshConfig? get vncSsh {
    if (protocol != HostProtocol.vnc) return null;
    final c = VncSshConfig.fromExtra(extra);
    return (c?.enabled ?? false) ? c : null;
  }

  /// 旧版配置：关联的独立 SSH 主机 uuid（兼容已有主机）
  String? get legacyTransferHost => VncSshConfig.fromExtra(extra) == null
      ? extra['transferHost'] as String?
      : null;

  /// 按内置配置生成连接用的 SSH 主机：沿用本主机的 uuid（主机指纹、记住的密码写回本主机）、地址、用户名与密码
  HostEntry asSshHost(VncSshConfig c) =>
      connectionProfile(HostProtocol.ssh) != null
      ? forConnection(HostProtocol.ssh)
      : copyWith(
          protocol: HostProtocol.ssh,
          port: c.port,
          authType: c.authType,
          keyUuid: () => c.authType == AuthType.key ? c.keyUuid : null,
          extra: const {},
        );
}
