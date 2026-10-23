import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;

import '../utils/platform_utils.dart';
import 'tables/ai_tables.dart';
import 'tables/host_tables.dart';
import 'tables/proxy_tables.dart';

export 'tables/ai_tables.dart';
export 'tables/host_tables.dart';
export 'tables/proxy_tables.dart';

part 'database.g.dart';

/// 应用数据库（drift ORM）。所有表均建立了查询所需的索引。
@DriftDatabase(
  tables: [HostGroups, Hosts, SshKeys, Snippets, AppSettings, AgentConfigs, ChatSessions, ChatMessages, TokenUsages, ProxyProfiles],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // 2：Agent 配置新增推理强度
      if (from < 2) await m.addColumn(agentConfigs, agentConfigs.reasoningEffort);
      // 3：代理配置集中管理；数据内容在主密钥初始化后迁移。
      if (from < 3) {
        await m.createTable(proxyProfiles);
        await m.addColumn(hosts, hosts.proxyUuid);
        for (final index in allSchemaEntities.whereType<Index>()) {
          if (index.entityName.startsWith('idx_proxies_') || index.entityName == 'idx_hosts_proxy_uuid') {
            await m.createIndex(index);
          }
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 打开应用数据目录下的 remlark.sqlite
  static QueryExecutor _open() {
    return driftDatabase(
      name: 'remlark',
      native: DriftNativeOptions(
        databasePath: () async {
          final dir = await PlatformUtils.dataDir();
          return p.join(dir.path, 'remlark.sqlite');
        },
      ),
    );
  }
}
