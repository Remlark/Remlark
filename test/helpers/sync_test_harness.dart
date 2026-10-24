import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/group_repository.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/keys/key_repository.dart';
import 'package:remlark/modules/settings/settings_repository.dart';
import 'package:remlark/modules/sync/host_sync_bundle.dart';
import 'package:remlark/modules/sync/sync_api.dart';
import 'package:remlark/modules/sync/sync_config.dart';
import 'package:remlark/modules/sync/sync_service.dart';
import 'package:remlark/utils/crypto_utils.dart';

/// 创建时间确定的主机，测试不依赖延时或真实时钟排序。
HostEntry syncHost({
  String uuid = 'h1',
  int version = 100,
  bool enabled = true,
  String name = 'Ubuntu',
}) => HostEntry(
  uuid: uuid,
  protocol: HostProtocol.ssh,
  name: name,
  address: 'ubuntu.example',
  port: 22,
  username: 'ubuntu',
  password: 'host-secret',
  savePassword: true,
  syncEnabled: enabled,
  createdAt: 1,
  updatedAt: version,
);

/// 所有非空协议组合的独立凭据夹具，第一种协议作为主协议。
HostEntry protocolHost(
  Set<HostProtocol> protocols, {
  int version = 100,
  bool remember = true,
}) {
  final ordered = HostProtocol.values.where(protocols.contains).toList();

  /// 为每种协议生成可辨认的独立参数。
  Map<String, dynamic> profile(HostProtocol protocol) => {
    'protocol': protocol.name,
    'port': protocol.defaultPort + 1,
    'username': '${protocol.name}-user',
    'authType': 'password',
    'savePassword': remember,
    if (remember) 'password': '${protocol.name}-secret',
    'proxy': {
      'type': 'socks5',
      'host': 'proxy.example',
      'port': 1080,
      'password': 'proxy-secret',
    },
    'extra': {
      if (protocol == HostProtocol.rdp) ...{
        'domain': 'office',
        'width': 1600,
        'height': 900,
        'clipboard': true,
      },
    },
  };
  final primary = ordered.first;
  return HostEntry.fromPortableJson({
    ...syncHost(version: version).toPortableJson(),
    ...profile(primary),
    'extra': {
      ...(profile(primary)['extra'] as Map),
      'osOverride': 'ubuntu',
      if (ordered.length > 1)
        'connections': {for (final p in ordered.skip(1)) p.name: profile(p)},
    },
  }).copyWith(syncEnabled: true);
}

/// 在内存中模拟 HTTP 接口的记录、冲突和竞态，密文仍由生产加密代码生成。
class MemorySyncApi extends SyncApi {
  MemorySyncApi() : super('https://unit.test', 'tok');

  final records = <String, RemoteItemPayload>{};
  int indexCalls = 0;
  int putCalls = 0;
  int fetchCalls = 0;
  int deleteCalls = 0;
  Future<void> Function()? beforeIndex;
  Future<void> Function()? beforePut;
  Future<void> Function()? beforeFetch;
  Object? indexError;
  Object? putError;
  Object? fetchError;
  Object? deleteError;
  bool omitFetched = false;

  static Future<List<int>>? _derivedKey;

  /// 与生产代码使用相同令牌盐和 PBKDF2 参数，只缓存夹具端的派生结果。
  static Future<List<int>> cryptoKey() => _derivedKey ??= () async {
    final salt = await CryptoUtils.sha256(utf8.encode('remlark-sync:tok'));
    return CryptoUtils.deriveKey('pass', salt);
  }();

  /// 写入任意格式载荷，可验证兼容、损坏和身份错配场景。
  Future<void> seedJson(
    String uuid,
    int version,
    Map<String, dynamic> json,
  ) async {
    final cipher = await CryptoUtils.encryptString(
      await cryptoKey(),
      jsonEncode(json),
    );
    records[uuid] = RemoteItemPayload(uuid, version, false, cipher);
  }

  /// 写入一个完整主机快照。
  Future<void> seed(HostEntry host, {String? groupName}) => seedJson(
    host.uuid,
    host.updatedAt,
    HostSyncBundle(host: host, groupName: groupName, keys: const []).toJson(),
  );

  /// 将记录变为删除标记，模拟其他客户端删除。
  void tombstone(String uuid, {int version = 999}) {
    records[uuid] = RemoteItemPayload(uuid, version, true, null);
  }

  /// 检查上传内容时只解密夹具保存的密文。
  Future<Map<String, dynamic>> decoded(String uuid) async => jsonDecode(
    await CryptoUtils.decryptCompressedString(
      await cryptoKey(),
      records[uuid]!.payload!,
    ),
  ) as Map<String, dynamic>;

  @override
  Future<void> ping() async {}

  /// 获取索引前允许注入可控的阻塞或网络错误。
  @override
  Future<Map<String, RemoteItemInfo>> index() async {
    indexCalls++;
    await beforeIndex?.call();
    if (indexError != null) throw indexError!;
    return {
      for (final item in records.values)
        item.uuid: RemoteItemInfo(item.uuid, item.updatedAt, item.deleted),
    };
  }

  /// 批量下载返回读取时刻的版本和删除状态。
  @override
  Future<Map<String, RemoteItemPayload>> fetch(List<String> uuids) async {
    fetchCalls++;
    await beforeFetch?.call();
    if (fetchError != null) throw fetchError!;
    return {
      if (!omitFetched)
        for (final id in uuids)
          if (records[id] != null) id: records[id]!,
    };
  }

  /// 按生产服务器的更新时间规则返回上传成功或冲突。
  @override
  Future<bool> put(
    String uuid,
    int updatedAt,
    String payload, {
    bool restoreDeleted = false,
  }) async {
    putCalls++;
    await beforePut?.call();
    if (putError != null) throw putError!;
    final old = records[uuid];
    if (old?.deleted == true && !restoreDeleted) return false;
    if (old != null &&
        !old.deleted &&
        (old.updatedAt > updatedAt ||
            (old.updatedAt == updatedAt && old.payload != payload))) {
      return false;
    }
    records[uuid] = RemoteItemPayload(uuid, updatedAt, false, payload);
    return true;
  }

  /// 删除失败时保留远端状态，成功时模拟服务器生成删除标记。
  @override
  Future<void> delete(String uuid) async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
    if (records.containsKey(uuid)) tombstone(uuid);
  }
}

/// 每个测试使用独立内存数据库，事务、加密和仓库调用均走生产实现。
class SyncTestClient {
  SyncTestClient(
    MemorySyncApi api, {
    HostRepository Function(AppDatabase)? hostFactory,
  }) {
    db = AppDatabase(NativeDatabase.memory());
    hosts = hostFactory?.call(db) ?? HostRepository(db);
    keys = KeyRepository(db);
    groups = GroupRepository(db);
    sync = SyncService(
      SettingsRepository(db),
      hosts,
      groups,
      keys,
      apiFactory: (_, _) => api,
    );
    sync.config = const SyncConfig(
      serverUrl: 'https://unit.test',
      token: 'tok',
      passphrase: 'pass',
    );
    addTearDown(() async {
      sync.dispose();
      keys.dispose();
      await db.close();
    });
  }

  late final AppDatabase db;
  late final HostRepository hosts;
  late final KeyRepository keys;
  late final GroupRepository groups;
  late final SyncService sync;

  /// 使用指定版本保存夹具，避免生产 save 刷新时间戳。
  Future<void> save(HostEntry host) async => hosts.save(host, touch: false);
}
