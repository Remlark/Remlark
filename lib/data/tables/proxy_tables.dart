import 'package:drift/drift.dart';

/// 可复用的出口代理；密码只以密文保存。
@TableIndex(name: 'idx_proxies_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_proxies_name', columns: {#name})
@TableIndex(name: 'idx_proxies_endpoint', columns: {#type, #host, #port, #username})
class ProxyProfiles extends Table {
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  TextColumn get type => text()();
  TextColumn get host => text()();
  IntColumn get port => integer()();
  TextColumn get username => text().withDefault(const Constant(''))();
  TextColumn get passwordEnc => text().nullable()();
  IntColumn get updatedAt => integer()();

  /// 主键用于编辑、选择与主机关联。
  @override
  Set<Column> get primaryKey => {uuid};
}
