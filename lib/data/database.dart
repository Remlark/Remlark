import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;

import '../utils/platform_utils.dart';
import 'tables/ai_tables.dart';
import 'tables/host_tables.dart';

export 'tables/ai_tables.dart';
export 'tables/host_tables.dart';

part 'database.g.dart';

/// 应用数据库（drift ORM）。所有表均建立了查询所需的索引。
@DriftDatabase(
  tables: [HostGroups, Hosts, SshKeys, Snippets, AppSettings, AgentConfigs, ChatSessions, ChatMessages, TokenUsages],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
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
