import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/hosts/host_model.dart';
import 'package:remlark/modules/hosts/host_repository.dart';
import 'package:remlark/modules/proxies/proxy_profile.dart';
import 'package:remlark/modules/proxies/proxy_repository.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

/// 构造有同步快照的旧版主机配置。
HostEntry _host(String uuid, ProxyConfig config) => HostEntry(
  uuid: uuid,
  name: uuid,
  protocol: HostProtocol.ssh,
  address: '192.0.2.1',
  port: 22,
  proxy: config,
  createdAt: 1,
  updatedAt: 2,
  syncedAt: 2,
  syncEnabled: true,
);

/// 验证共享代理的加密、引用一致性、去重及旧数据库兼容。
void main() {
  late AppDatabase db;
  late HostRepository hosts;
  late ProxyRepository proxies;
  const config = ProxyConfig(
    type: ProxyType.socks5,
    host: 'proxy.example.com',
    port: 1080,
    username: 'user',
    password: 'secret-value',
  );

  setUp(() {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    db = AppDatabase(NativeDatabase.memory());
    hosts = HostRepository(db);
    proxies = ProxyRepository(db);
  });
  tearDown(() => db.close());

  test('迁移旧代理保留同步时间，完整凭据相同才合并，重复运行无副作用', () async {
    final password = await SecretStore.instance.seal(config.password);
    for (final id in ['old-a', 'old-b']) {
      await db
          .into(db.hosts)
          .insert(
            HostsCompanion.insert(
              uuid: id,
              protocol: 'ssh',
              name: id,
              address: '192.0.2.1',
              port: 22,
              proxyType: const Value('socks5'),
              proxyHost: Value(config.host),
              proxyPort: Value(config.port),
              proxyUser: Value(config.username),
              proxyPassEnc: Value(password),
              createdAt: 1,
              updatedAt: 2,
              syncEnabled: const Value(true),
              syncedAt: const Value(2),
            ),
          );
    }
    await hosts.migrateInlineProxies();
    await hosts.migrateInlineProxies();
    final a = (await hosts.getByUuid('old-a'))!;
    final b = (await hosts.getByUuid('old-b'))!;
    expect(a.proxyUuid, isNotNull);
    expect(a.proxyUuid, b.proxyUuid);
    expect(
      (a.updatedAt, a.syncedAt, a.proxy.password),
      (2, 2, config.password),
    );
    expect(await proxies.list(), hasLength(1));
    await hosts.save(
      _host(
        'different-secret',
        ProxyConfig(
          type: config.type,
          host: config.host,
          port: config.port,
          username: config.username,
          password: 'another',
        ),
      ),
    );
    expect(await proxies.list(), hasLength(2));
    final row = await (db.select(
      db.proxyProfiles,
    )..where((t) => t.uuid.equals(a.proxyUuid!))).getSingle();
    expect(row.passwordEnc, isNot(contains(config.password!)));
    expect(await SecretStore.instance.open(row.passwordEnc), config.password);
  });

  test('编辑代理更新所有引用的快照，旧会话重新解析可取最新参数，使用中禁止删除', () async {
    final a = await hosts.save(_host('a', config), touch: false);
    final b = await hosts.save(_host('b', config), touch: false);
    await proxies.save(
      ProxyEntry(uuid: a.proxyUuid!, name: 'Renamed', config: config),
    );
    expect(
      (await hosts.getByUuid(a.uuid))!.updatedAt,
      2,
      reason: '仅重命名不改变主机同步状态',
    );
    const changed = ProxyConfig(
      type: ProxyType.http,
      host: 'new.example.com',
      port: 8080,
      password: 'new-secret',
    );
    await proxies.save(
      ProxyEntry(uuid: a.proxyUuid!, name: 'Office', config: changed),
    );
    for (final id in [a.uuid, b.uuid]) {
      final current = (await hosts.getByUuid(id))!;
      expect(current.proxy.toJson(), changed.toJson());
      expect(current.updatedAt, greaterThan(2));
      expect(current.syncedAt, 2);
    }
    expect((await hosts.resolveProxy(a)).proxy.toJson(), changed.toJson());
    expect(await proxies.usageCounts(), {a.proxyUuid: 2});
    expect(await proxies.delete(a.proxyUuid!), isFalse);
    await hosts.save(
      a.copyWith(proxyUuid: () => null, proxy: const ProxyConfig()),
    );
    await hosts.delete(b.uuid);
    expect(await proxies.delete(a.proxyUuid!), isTrue);
    await expectLater(hosts.resolveProxy(a), throwsStateError);
  });

  test('可移植配置不输出本地引用，导入时恢复可用代理，去除敏感信息时不泄露密码', () async {
    final local = await hosts.save(_host('portable', config));
    final portable = local.toPortableJson();
    expect(portable.containsKey('proxyUuid'), isFalse);
    expect((portable['proxy'] as Map)['password'], config.password);
    expect(
      (local.toPortableJson(withSecrets: false)['proxy'] as Map).containsKey(
        'password',
      ),
      isFalse,
    );
    final imported = await hosts.save(
      HostEntry.fromPortableJson(portable).copyWith(uuid: 'imported'),
    );
    expect(imported.proxyUuid, local.proxyUuid);
    expect(imported.proxy.toJson(), config.toJson());
  });

  test('schema 2 升级创建代理表、引用列及索引，旧主机代理与凭据仍可迁移', () async {
    final old = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          // 模拟 schema 2 的真实旧表；SQL 仅用于构造旧版本 fixture。
          raw.execute('''CREATE TABLE hosts (
        id INTEGER PRIMARY KEY AUTOINCREMENT, uuid TEXT NOT NULL, protocol TEXT NOT NULL,
        name TEXT NOT NULL, group_uuid TEXT, address TEXT NOT NULL, port INTEGER NOT NULL,
        username TEXT NOT NULL DEFAULT '', auth_type TEXT NOT NULL DEFAULT 'password',
        password_enc TEXT, save_password INTEGER NOT NULL DEFAULT 0, key_uuid TEXT,
        jump_chain TEXT NOT NULL DEFAULT '[]', proxy_type TEXT NOT NULL DEFAULT 'none',
        proxy_host TEXT NOT NULL DEFAULT '', proxy_port INTEGER NOT NULL DEFAULT 0,
        proxy_user TEXT NOT NULL DEFAULT '', proxy_pass_enc TEXT, os_id TEXT, os_name TEXT,
        host_key_fingerprint TEXT, extra_json TEXT NOT NULL DEFAULT '{}', note TEXT NOT NULL DEFAULT '',
        sync_enabled INTEGER NOT NULL DEFAULT 0, synced_at INTEGER, updated_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL, last_connected_at INTEGER)''');
          raw.execute(
            "INSERT INTO hosts(uuid,protocol,name,address,port,proxy_type,proxy_host,proxy_port,updated_at,created_at) VALUES ('old','rdp','Old','192.0.2.1',3389,'http','office.example.com',8080,2,1)",
          );
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(old.close);
    final repository = HostRepository(old);
    await repository.migrateInlineProxies();
    final migrated = (await repository.getByUuid('old'))!;
    expect(migrated.proxyUuid, isNotNull);
    expect(migrated.proxy.host, 'office.example.com');
    expect(
      (await ProxyRepository(old).list()).single.config.type,
      ProxyType.http,
    );
    expect(migrated.updatedAt, 2);
  });
}
