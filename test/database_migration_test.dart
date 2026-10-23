import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/data/database.dart';
import 'package:remlark/modules/ai/agent_repository.dart';
import 'package:remlark/utils/crypto_utils.dart';
import 'package:remlark/utils/secret_store.dart';

void main() {
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
