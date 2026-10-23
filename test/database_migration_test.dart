import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/ai/agent_repository.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

/// 数据库升级回归：旧版、部分升级及失败回滚均保留原有数据。
void main() {
  for (final partial in [true, false]) {
    test('版本 2 已含代理列，${partial ? '部分' : '全部'}索引存在时可恢复并重复打开', () async {
      final dir = await Directory.systemTemp.createTemp('remlark-migration-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/test.sqlite');
      final seed = AppDatabase(NativeDatabase(file));
      // 使用 ORM 创建完整现有结构，再模拟版本号未更新的历史数据库。
      await seed
          .into(seed.hosts)
          .insert(
            HostsCompanion.insert(
              uuid: 'keep-host',
              protocol: 'ssh',
              name: 'Keep',
              address: '192.0.2.1',
              port: 22,
              updatedAt: 2,
              createdAt: 1,
            ),
          );
      await seed
          .into(seed.proxyProfiles)
          .insert(
            ProxyProfilesCompanion.insert(
              uuid: 'keep-proxy',
              name: 'Keep proxy',
              type: 'http',
              host: 'proxy.example',
              port: 8080,
              updatedAt: 1,
            ),
          );
      await seed.close();
      final raw = sqlite3.open(file.path);
      raw.execute('PRAGMA user_version = 2');
      if (partial) {
        raw.execute('DROP INDEX idx_proxies_endpoint');
        raw.execute('DROP INDEX idx_hosts_proxy_uuid');
      }
      raw.close();
      for (var attempt = 0; attempt < 2; attempt++) {
        final restored = AppDatabase(NativeDatabase(file));
        try {
          final host = await (restored.select(restored.hosts)..where((h) => h.uuid.equals('keep-host'))).getSingle();
          final proxy = await (restored.select(
            restored.proxyProfiles,
          )..where((p) => p.uuid.equals('keep-proxy'))).getSingle();
          expect((host.name, host.address), ('Keep', '192.0.2.1'));
          expect((proxy.name, proxy.host), ('Keep proxy', 'proxy.example'));
          expect((await restored.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 3);
          final indexes = await restored
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND (name LIKE 'idx_proxies_%' OR name = 'idx_hosts_proxy_uuid')",
              )
              .get();
          expect(indexes, hasLength(4));
        } finally {
          await restored.close();
        }
      }
    });
  }

  test('迁移中途失败时新列回滚，旧版本号和原数据保留', () async {
    final dir = await Directory.systemTemp.createTemp('remlark-migration-rollback-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute('CREATE TABLE hosts (uuid TEXT PRIMARY KEY)');
    raw.execute("INSERT INTO hosts (uuid) VALUES ('keep')");
    // 缺失 name 的异常旧表会让后续索引创建失败，用于验证前面新增列一同回滚。
    raw.execute('CREATE TABLE proxy_profiles (uuid TEXT PRIMARY KEY)');
    raw.execute('PRAGMA user_version = 2');
    raw.close();
    final db = AppDatabase(NativeDatabase(file));
    try {
      await expectLater(db.customSelect('SELECT 1').get(), throwsA(isA<SqliteException>()));
    } finally {
      await db.close();
    }
    final check = sqlite3.open(file.path);
    try {
      expect(check.select('PRAGMA user_version').single['user_version'], 2);
      expect(check.select('PRAGMA table_info(hosts)').map((r) => r['name']), ['uuid']);
      expect(check.select("SELECT uuid FROM hosts WHERE uuid = 'keep'").single['uuid'], 'keep');
    } finally {
      check.close();
    }
  });

  // schema 1 → 2：agent_configs 新增 reasoning_effort，旧数据保留且默认为空（模型默认）
  test('升级到 schema 2 后保留旧 Agent 并可保存推理强度', () async {
    SecretStore.initForTest(CryptoUtils.randomBytes(32));
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          // 旧版本 fixture 同时包含主机表，供后续代理引用迁移使用。
          raw.execute('CREATE TABLE hosts (uuid TEXT NOT NULL PRIMARY KEY)');
          raw.execute('''
            CREATE TABLE agent_configs (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              uuid TEXT NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL,
              command TEXT NOT NULL DEFAULT '', args TEXT NOT NULL DEFAULT '', endpoint TEXT NOT NULL DEFAULT '',
              api_key_enc TEXT NULL, model TEXT NOT NULL DEFAULT '', system_prompt TEXT NOT NULL DEFAULT '',
              is_active INTEGER NOT NULL DEFAULT 0 CHECK (is_active IN (0, 1)), created_at INTEGER NOT NULL
            )''');
          raw.execute("INSERT INTO agent_configs (uuid, name, kind, created_at) VALUES ('old', 'Old', 'codex', 1)");
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    final repo = AgentRepository(db);
    final old = (await repo.list()).single;
    expect((old.uuid, old.reasoningEffort), ('old', ''));
    await repo.save(old.copyWith(reasoningEffort: 'high'));
    expect((await repo.list()).single.reasoningEffort, 'high');
    await db.close();
  });
}
