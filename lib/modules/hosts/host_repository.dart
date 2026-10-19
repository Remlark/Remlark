import 'dart:convert';

import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../utils/secret_store.dart';
import 'host_model.dart';

/// 主机仓库：负责主机表的读写，以及敏感字段的加解密
class HostRepository {
  HostRepository(this._db);

  final AppDatabase _db;

  SecretStore get _secrets => SecretStore.instance;

  /// 当前毫秒时间戳
  static int now() => DateTime.now().millisecondsSinceEpoch;

  /// 数据库行转领域模型（解密敏感字段）
  Future<HostEntry> _toEntry(Host r) async {
    Map<String, dynamic> extra;
    try {
      extra = Map<String, dynamic>.from(jsonDecode(r.extraJson) as Map);
    } catch (_) {
      extra = {};
    }
    List<String> chain;
    try {
      chain = (jsonDecode(r.jumpChain) as List).cast<String>();
    } catch (_) {
      chain = [];
    }
    return HostEntry(
      uuid: r.uuid,
      protocol: HostProtocol.parse(r.protocol),
      name: r.name,
      groupUuid: r.groupUuid,
      address: r.address,
      port: r.port,
      username: r.username,
      authType: AuthType.parse(r.authType),
      password: r.savePassword ? await _secrets.open(r.passwordEnc) : null,
      savePassword: r.savePassword,
      keyUuid: r.keyUuid,
      jumpChain: chain,
      proxy: ProxyConfig(
        type: ProxyType.parse(r.proxyType),
        host: r.proxyHost,
        port: r.proxyPort,
        username: r.proxyUser,
        password: await _secrets.open(r.proxyPassEnc),
      ),
      osId: r.osId,
      osName: r.osName,
      hostKeyFingerprint: r.hostKeyFingerprint,
      extra: extra,
      note: r.note,
      syncEnabled: r.syncEnabled,
      syncedAt: r.syncedAt,
      updatedAt: r.updatedAt,
      createdAt: r.createdAt,
      lastConnectedAt: r.lastConnectedAt,
    );
  }

  /// 领域模型转数据库写入对象（加密敏感字段）
  Future<HostsCompanion> _toCompanion(HostEntry e) async {
    return HostsCompanion(
      uuid: Value(e.uuid),
      protocol: Value(e.protocol.name),
      name: Value(e.name),
      groupUuid: Value(e.groupUuid),
      address: Value(e.address),
      port: Value(e.port),
      username: Value(e.username),
      authType: Value(e.authType.name),
      passwordEnc: Value(e.savePassword ? await _secrets.seal(e.password) : null),
      savePassword: Value(e.savePassword),
      keyUuid: Value(e.keyUuid),
      jumpChain: Value(jsonEncode(e.jumpChain)),
      proxyType: Value(e.proxy.type.name),
      proxyHost: Value(e.proxy.host),
      proxyPort: Value(e.proxy.port),
      proxyUser: Value(e.proxy.username),
      proxyPassEnc: Value(await _secrets.seal(e.proxy.password)),
      osId: Value(e.osId),
      osName: Value(e.osName),
      hostKeyFingerprint: Value(e.hostKeyFingerprint),
      extraJson: Value(jsonEncode(e.extra)),
      note: Value(e.note),
      syncEnabled: Value(e.syncEnabled),
      syncedAt: Value(e.syncedAt),
      updatedAt: Value(e.updatedAt),
      createdAt: Value(e.createdAt),
      lastConnectedAt: Value(e.lastConnectedAt),
    );
  }

  /// 按协议查询主机（走 protocol 索引）
  Future<List<HostEntry>> listByProtocols(Set<HostProtocol> protocols) async {
    final rows =
        await (_db.select(_db.hosts)
              ..where((t) => t.protocol.isIn(protocols.map((p) => p.name)))
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get();
    return Future.wait(rows.map(_toEntry));
  }

  /// 按 uuid 查询（唯一索引）
  Future<HostEntry?> getByUuid(String uuid) async {
    final row = await (_db.select(_db.hosts)..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    return row == null ? null : _toEntry(row);
  }

  /// 按多个 uuid 查询（唯一索引）
  Future<List<HostEntry>> getByUuids(Iterable<String> uuids) async {
    if (uuids.isEmpty) return [];
    final rows = await (_db.select(_db.hosts)..where((t) => t.uuid.isIn(uuids))).get();
    return Future.wait(rows.map(_toEntry));
  }

  /// 查询参与同步的主机（syncEnabled 索引）
  Future<List<HostEntry>> listSyncEnabled() async {
    final rows = await (_db.select(_db.hosts)..where((t) => t.syncEnabled.equals(true))).get();
    return Future.wait(rows.map(_toEntry));
  }

  /// 保存主机（按 uuid 插入或更新）。[touch] 为 true 时刷新 updatedAt
  Future<HostEntry> save(HostEntry e, {bool touch = true}) async {
    final entry = touch ? e.copyWith(updatedAt: now()) : e;
    final comp = await _toCompanion(entry);
    final existing = await (_db.select(_db.hosts)..where((t) => t.uuid.equals(entry.uuid))).getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.hosts).insert(comp);
    } else {
      await (_db.update(_db.hosts)..where((t) => t.uuid.equals(entry.uuid))).write(comp);
    }
    return entry;
  }

  /// 删除主机（跳板链引用由控制器负责清理）
  Future<void> delete(String uuid) async {
    await (_db.delete(_db.hosts)..where((t) => t.uuid.equals(uuid))).go();
  }

  /// 更新探测到的系统信息（不影响同步时间戳）
  Future<void> updateOs(String uuid, String? osId, String? osName) async {
    await (_db.update(
      _db.hosts,
    )..where((t) => t.uuid.equals(uuid))).write(HostsCompanion(osId: Value(osId), osName: Value(osName)));
  }

  /// 记录主机指纹（不影响同步时间戳）
  Future<void> updateFingerprint(String uuid, String fp) async {
    await (_db.update(
      _db.hosts,
    )..where((t) => t.uuid.equals(uuid))).write(HostsCompanion(hostKeyFingerprint: Value(fp)));
  }

  /// 记录最后连接时间（不影响同步时间戳）
  Future<void> touchConnected(String uuid) async {
    await (_db.update(
      _db.hosts,
    )..where((t) => t.uuid.equals(uuid))).write(HostsCompanion(lastConnectedAt: Value(now())));
  }

  /// 保存（或清除）密码；属于配置变更，会刷新 updatedAt
  Future<void> updatePassword(String uuid, String? password, bool save) async {
    await (_db.update(_db.hosts)..where((t) => t.uuid.equals(uuid))).write(
      HostsCompanion(
        savePassword: Value(save),
        passwordEnc: Value(save ? await _secrets.seal(password) : null),
        updatedAt: Value(now()),
      ),
    );
  }

  /// 设置同步状态（不影响 updatedAt）
  Future<void> setSyncState(String uuid, {required bool enabled, int? syncedAt}) async {
    await (_db.update(
      _db.hosts,
    )..where((t) => t.uuid.equals(uuid))).write(HostsCompanion(syncEnabled: Value(enabled), syncedAt: Value(syncedAt)));
  }

  /// 查询引用了某个分组的主机，并清空其分组（protocol+group 复合索引不覆盖单独 group，
  /// 因此通过遍历所有协议值以使用索引前缀）
  Future<void> clearGroup(String groupUuid) async {
    await (_db.update(_db.hosts)
          ..where((t) => t.protocol.isIn(HostProtocol.values.map((p) => p.name)) & t.groupUuid.equals(groupUuid)))
        .write(const HostsCompanion(groupUuid: Value(null)));
  }
}
