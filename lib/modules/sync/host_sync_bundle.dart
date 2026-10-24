import '../hosts/host_model.dart';
import '../hosts/vnc_ssh_config.dart';
import '../keys/key_model.dart';

/// 一个主机的完整同步快照：所有连接方式共享同一身份、版本和同步状态。
class HostSyncBundle {
  const HostSyncBundle({
    required this.host,
    required this.keys,
    this.groupName,
  });

  /// 第二版仍保留旧载荷的 host/group/key 字段，新增多密钥列表。
  static const version = 2;

  final HostEntry host;
  final String? groupName;
  final List<KeyEntry> keys;

  /// 收集一个主机所有连接方式使用的 SSH 密钥，不按协议拆成服务器记录。
  static Set<String> referencedKeyUuids(HostEntry host) => {
    for (final protocol in host.connectionProtocols)
      if (host.forConnection(protocol).keyUuid case final String id) id,
  };

  /// 写出单条主机载荷，保留旧客户端识别的主协议密钥字段。
  Map<String, dynamic> toJson() => {
    'version': version,
    'host': host.toPortableJson(),
    if (groupName != null) 'group': groupName,
    if (host.keyUuid != null)
      for (final key in keys)
        if (key.uuid == host.keyUuid) 'key': key.toJson(),
    'keys': [for (final key in keys) key.toJson()],
  };

  /// 读取新版或旧版单密钥载荷；未知新版本直接报错，避免覆盖本机完整配置。
  factory HostSyncBundle.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['version'];
    if (rawVersion != null &&
        (rawVersion is! int || rawVersion < 1 || rawVersion > version)) {
      throw FormatException('Unsupported host sync version: $rawVersion');
    }
    final rawHost = json['host'];
    if (rawHost is! Map) {
      throw const FormatException('Missing host sync payload');
    }
    final hostJson = Map<String, dynamic>.from(rawHost);
    _validateProtocols(hostJson);
    final host = HostEntry.fromPortableJson(hostJson);
    final keysById = <String, KeyEntry>{};
    final legacyKey = json['key'];
    if (legacyKey != null && legacyKey is! Map) {
      throw const FormatException('Invalid legacy host sync key');
    }
    if (legacyKey is Map) {
      final key = KeyEntry.fromJson(Map<String, dynamic>.from(legacyKey));
      keysById[key.uuid] = key;
    }
    final rawKeys = json['keys'];
    if (rawKeys != null && rawKeys is! List) {
      throw const FormatException('Invalid host sync keys');
    }
    if (rawKeys is List) {
      for (final item in rawKeys) {
        if (item is! Map) throw const FormatException('Invalid host sync key');
        final key = KeyEntry.fromJson(Map<String, dynamic>.from(item));
        keysById[key.uuid] = key;
      }
    }
    final referenced = referencedKeyUuids(host);
    return HostSyncBundle(
      host: host,
      groupName: json['group'] as String?,
      keys: [
        for (final key in keysById.values)
          if (referenced.contains(key.uuid)) key,
      ],
    );
  }

  /// 同步不能将未知连接方式静默解析为 SSH，否则会覆盖主机原有配置。
  static void _validateProtocols(Map<String, dynamic> host) {
    final names = HostProtocol.values.map((p) => p.name).toSet();
    if (!names.contains(host['protocol'])) {
      throw const FormatException('Invalid host sync protocol');
    }
    final extra = host['extra'];
    if (extra == null) return;
    if (extra is! Map) throw const FormatException('Invalid host sync extra');
    final profiles = extra['connections'];
    if (profiles == null) return;
    if (profiles is! Map) {
      throw const FormatException('Invalid host sync connections');
    }
    for (final item in profiles.entries) {
      final profile = item.value;
      if (!names.contains(item.key) ||
          profile is! Map ||
          (profile['protocol'] != null && profile['protocol'] != item.key)) {
        throw const FormatException('Invalid host sync connection protocol');
      }
    }
  }

  /// 校验密文中的主机身份与服务端索引一致，防止错误载荷覆盖另一台主机。
  void verifyServerRecord(String uuid, int updatedAt) {
    if (host.uuid != uuid || host.updatedAt != updatedAt) {
      throw const FormatException('Host sync identity or version mismatch');
    }
  }

  /// 拉取时仅保留本机状态；同一协议的端点不变才沿用本机信任指纹。
  HostEntry forDevice({
    required HostEntry? local,
    required String? groupUuid,
    required int updatedAt,
  }) {
    /// 查找本机同协议且地址、端口都未变化的连接。
    HostEntry? matchingLocalConnection(HostProtocol protocol, int port) {
      if (local == null || !local.connectionProtocols.contains(protocol)) {
        return null;
      }
      final connection = local.forConnection(protocol);
      return connection.address == host.address && connection.port == port
          ? connection
          : null;
    }

    final extra = Map<String, dynamic>.from(host.extra);
    final incomingProfiles = extra['connections'];
    if (incomingProfiles is Map) {
      final profiles = <String, dynamic>{};
      for (final item in incomingProfiles.entries) {
        final profile = Map<String, dynamic>.from(item.value as Map)
          ..remove('hostKeyFingerprint');
        final protocol = HostProtocol.values
            .where((p) => p.name == item.key)
            .firstOrNull;
        final port = (profile['port'] as num?)?.toInt();
        final fingerprint = protocol == null || port == null
            ? null
            : matchingLocalConnection(protocol, port)?.hostKeyFingerprint;
        if (fingerprint != null) {
          profile['hostKeyFingerprint'] = fingerprint;
        }
        profiles[item.key as String] = profile;
      }
      extra['connections'] = profiles;
    }
    return host.copyWith(
      groupUuid: () => groupUuid,
      extra: extra,
      updatedAt: updatedAt,
      syncEnabled: true,
      syncedAt: () => updatedAt,
      hostKeyFingerprint: () =>
          matchingLocalConnection(host.protocol, host.port)?.hostKeyFingerprint,
      lastConnectedAt: () => local?.lastConnectedAt,
      osId: () => host.osId ?? local?.osId,
      osName: () => host.osName ?? local?.osName,
    );
  }
}
