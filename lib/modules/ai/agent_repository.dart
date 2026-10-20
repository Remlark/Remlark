import 'package:drift/drift.dart';

import '../../data/database.dart';
import '../../utils/secret_store.dart';
import 'agent_config.dart';

/// Agent 配置仓库
class AgentRepository {
  AgentRepository(this._db);

  final AppDatabase _db;

  SecretStore get _secrets => SecretStore.instance;

  Future<AgentSettings> _toSettings(AgentConfig r) async => AgentSettings(
    uuid: r.uuid,
    name: r.name,
    kind: AgentKind.parse(r.kind),
    command: r.command,
    args: r.args,
    endpoint: r.endpoint,
    apiKey: await _secrets.open(r.apiKeyEnc),
    model: r.model,
    systemPrompt: r.systemPrompt,
    reasoningEffort: r.reasoningEffort,
    isActive: r.isActive,
    createdAt: r.createdAt,
  );

  /// 列出全部 Agent（按创建时间索引）
  Future<List<AgentSettings>> list() async {
    final rows =
        await (_db.select(_db.agentConfigs)
              ..where((t) => t.createdAt.isBiggerOrEqualValue(0))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
            .get();
    return Future.wait(rows.map(_toSettings));
  }

  /// 当前使用的 Agent（isActive 索引）
  Future<AgentSettings?> active() async {
    final r =
        await (_db.select(_db.agentConfigs)
              ..where((t) => t.isActive.equals(true))
              ..limit(1))
            .getSingleOrNull();
    return r == null ? null : _toSettings(r);
  }

  /// 保存
  Future<void> save(AgentSettings a) async {
    final comp = AgentConfigsCompanion(
      uuid: Value(a.uuid),
      name: Value(a.name),
      kind: Value(a.kind.value),
      command: Value(a.command),
      args: Value(a.args),
      endpoint: Value(a.endpoint),
      apiKeyEnc: Value(await _secrets.seal(a.apiKey)),
      model: Value(a.model),
      systemPrompt: Value(a.systemPrompt),
      reasoningEffort: Value(a.reasoningEffort),
      isActive: Value(a.isActive),
      createdAt: Value(a.createdAt),
    );
    final exists = await (_db.select(_db.agentConfigs)..where((t) => t.uuid.equals(a.uuid))).getSingleOrNull();
    if (exists == null) {
      await _db.into(_db.agentConfigs).insert(comp);
    } else {
      await (_db.update(_db.agentConfigs)..where((t) => t.uuid.equals(a.uuid))).write(comp);
    }
  }

  /// 设为当前使用的 Agent（其余取消）
  Future<void> setActive(String uuid) async {
    await _db.transaction(() async {
      await (_db.update(
        _db.agentConfigs,
      )..where((t) => t.isActive.equals(true))).write(const AgentConfigsCompanion(isActive: Value(false)));
      await (_db.update(
        _db.agentConfigs,
      )..where((t) => t.uuid.equals(uuid))).write(const AgentConfigsCompanion(isActive: Value(true)));
    });
  }

  /// 删除
  Future<void> delete(String uuid) async {
    await (_db.delete(_db.agentConfigs)..where((t) => t.uuid.equals(uuid))).go();
  }
}
