import 'package:drift/drift.dart';

/// 主机分组表
@TableIndex(name: 'idx_groups_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_groups_sort', columns: {#sortOrder})
class HostGroups extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()();
}

/// 主机表：SSH / RDP / VNC 共用，协议相关的额外配置放在 extraJson
@TableIndex(name: 'idx_hosts_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_hosts_protocol_group', columns: {#protocol, #groupUuid})
@TableIndex(name: 'idx_hosts_sync', columns: {#syncEnabled})
@TableIndex(name: 'idx_hosts_last_connected', columns: {#lastConnectedAt})
class Hosts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();

  /// 协议：ssh / rdp / vnc
  TextColumn get protocol => text()();
  TextColumn get name => text()();
  TextColumn get groupUuid => text().nullable()();
  TextColumn get address => text()();
  IntColumn get port => integer()();
  TextColumn get username => text().withDefault(const Constant(''))();

  /// 认证方式：password / key / keyboard
  TextColumn get authType => text().withDefault(const Constant('password'))();
  TextColumn get passwordEnc => text().nullable()();
  BoolColumn get savePassword => boolean().withDefault(const Constant(false))();
  TextColumn get keyUuid => text().nullable()();

  /// 跳板链：JSON 数组，元素为主机 uuid，按连接顺序排列
  TextColumn get jumpChain => text().withDefault(const Constant('[]'))();

  /// 出口代理：none / http / socks5
  TextColumn get proxyType => text().withDefault(const Constant('none'))();
  TextColumn get proxyHost => text().withDefault(const Constant(''))();
  IntColumn get proxyPort => integer().withDefault(const Constant(0))();
  TextColumn get proxyUser => text().withDefault(const Constant(''))();
  TextColumn get proxyPassEnc => text().nullable()();

  /// 自动探测到的系统 id（如 ubuntu、rhel）与可读名称
  TextColumn get osId => text().nullable()();
  TextColumn get osName => text().nullable()();

  /// 首次连接记录的主机指纹（TOFU）
  TextColumn get hostKeyFingerprint => text().nullable()();
  TextColumn get extraJson => text().withDefault(const Constant('{}'))();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// 是否参与同步，以及最后一次与服务器一致时的服务器更新时间
  BoolColumn get syncEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get syncedAt => integer().nullable()();
  IntColumn get updatedAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get lastConnectedAt => integer().nullable()();
}

/// SSH 密钥表
@TableIndex(name: 'idx_keys_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_keys_created', columns: {#createdAt})
class SshKeys extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  TextColumn get keyType => text()();
  TextColumn get privateKeyEnc => text()();
  TextColumn get passphraseEnc => text().nullable()();
  TextColumn get publicKey => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

/// 快捷指令表
@TableIndex(name: 'idx_snippets_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_snippets_sort', columns: {#sortOrder})
class Snippets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text()();
  TextColumn get name => text()();
  TextColumn get content => text().withDefault(const Constant(''))();

  /// 类型：text（普通字符串）/ install_system_key（系统免密登录动作）
  TextColumn get kind => text().withDefault(const Constant('text'))();

  /// 是否在发送后自动回车
  BoolColumn get autoEnter => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()();
}

/// 设置表（键值对）
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
