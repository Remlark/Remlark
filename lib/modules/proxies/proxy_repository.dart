import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../utils/id_utils.dart';
import '../../utils/secret_store.dart';
import '../hosts/host_model.dart';
import 'proxy_profile.dart';

/// 代理仓库：索引查询、凭据加密及引用快照的事务更新。
class ProxyRepository {
  ProxyRepository(this._db);

  final AppDatabase _db;

  /// 解密为仅存在内存中的连接配置。
  Future<ProxyEntry> _entry(ProxyProfile row) async => ProxyEntry(
    uuid: row.uuid,
    name: row.name,
    config: ProxyConfig(
      type: ProxyType.parse(row.type),
      host: row.host,
      port: row.port,
      username: row.username,
      password: await SecretStore.instance.open(row.passwordEnc),
    ),
  );

  /// 按协议索引前缀查询支持的代理，再按名称排列。
  Future<List<ProxyEntry>> list() async {
    final rows =
        await (_db.select(_db.proxyProfiles)
              ..where((t) => t.type.isIn(['http', 'socks5']))
              ..orderBy([(t) => OrderingTerm.asc(t.name)]))
            .get();
    return Future.wait(rows.map(_entry));
  }

  /// 按唯一标识查询代理。
  Future<ProxyEntry?> get(String uuid) async {
    final row = await (_db.select(
      _db.proxyProfiles,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
    return row == null ? null : _entry(row);
  }

  /// 保存代理并原子刷新引用主机快照；已建立的会话不受影响。
  Future<void> save(ProxyEntry entry) => _db.transaction(() async {
    final c = entry.config;
    final previous = await get(entry.uuid);
    final now = DateTime.now().millisecondsSinceEpoch;
    final encrypted = await SecretStore.instance.seal(c.password);
    await _db
        .into(_db.proxyProfiles)
        .insertOnConflictUpdate(
          ProxyProfilesCompanion.insert(
            uuid: entry.uuid,
            name: entry.name,
            type: c.type.name,
            host: c.host,
            port: c.port,
            username: Value(c.username),
            passwordEnc: Value(encrypted),
            updatedAt: now,
          ),
        );
    // 仅重命名不影响连接参数，也不把引用主机标记为待同步。
    if (previous != null && previous.config.sameConnectionAs(c)) return;
    await (_db.update(
      _db.hosts,
    )..where((t) => t.proxyUuid.equals(entry.uuid))).write(
      HostsCompanion(
        proxyType: Value(c.type.name),
        proxyHost: Value(c.host),
        proxyPort: Value(c.port),
        proxyUser: Value(c.username),
        proxyPassEnc: Value(encrypted),
        updatedAt: Value(now),
      ),
    );
  });

  /// 旧配置、同步与导入以完整凭据去重，避免不同账户的同一端点被误合并。
  Future<ProxyEntry> ensureConfig(
    ProxyConfig config,
  ) => _db.transaction(() async {
    final rows =
        await (_db.select(_db.proxyProfiles)..where(
              (t) =>
                  t.type.equals(config.type.name) &
                  t.host.equals(config.host) &
                  t.port.equals(config.port) &
                  t.username.equals(config.username),
            ))
            .get();
    for (final row in rows) {
      final entry = await _entry(row);
      if (entry.config.sameConnectionAs(config)) return entry;
    }
    final base =
        '${config.type.name.toUpperCase()} · ${config.host}:${config.port}${config.username.isEmpty ? '' : ' · ${config.username}'}';
    var name = base;
    var suffix = 2;
    // 旧主机可能只在密码上不同，名称加序号以便在选择器中区分。
    while (await (_db.select(_db.proxyProfiles)
              ..where((t) => t.name.equals(name))
              ..limit(1))
            .getSingleOrNull() !=
        null) {
      name = '$base (${suffix++})';
    }
    final entry = ProxyEntry(uuid: IdUtils.newId(), name: name, config: config);
    await save(entry);
    return entry;
  });

  /// 按代理引用索引汇总使用数量，空引用不参与统计。
  Future<Map<String, int>> usageCounts() async {
    final count = _db.hosts.uuid.count();
    final query = _db.selectOnly(_db.hosts)
      ..addColumns([_db.hosts.proxyUuid, count])
      ..where(_db.hosts.proxyUuid.isNotNull())
      ..groupBy([_db.hosts.proxyUuid]);
    return {
      for (final row in await query.get())
        row.read(_db.hosts.proxyUuid)!: row.read(count)!,
    };
  }

  /// 使用中的代理禁止删除，避免主机意外回退为直接连接。
  Future<bool> delete(String uuid) => _db.transaction(() async {
    final reference =
        await (_db.select(_db.hosts)
              ..where((t) => t.proxyUuid.equals(uuid))
              ..limit(1))
            .getSingleOrNull();
    if (reference != null) return false;
    await (_db.delete(
      _db.proxyProfiles,
    )..where((t) => t.uuid.equals(uuid))).go();
    return true;
  });
}
