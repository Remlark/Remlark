// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $HostGroupsTable extends HostGroups
    with TableInfo<$HostGroupsTable, HostGroup> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, uuid, name, sortOrder, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'host_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<HostGroup> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HostGroup map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HostGroup(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $HostGroupsTable createAlias(String alias) {
    return $HostGroupsTable(attachedDatabase, alias);
  }
}

class HostGroup extends DataClass implements Insertable<HostGroup> {
  final int id;
  final String uuid;
  final String name;
  final int sortOrder;
  final int updatedAt;
  const HostGroup({
    required this.id,
    required this.uuid,
    required this.name,
    required this.sortOrder,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  HostGroupsCompanion toCompanion(bool nullToAbsent) {
    return HostGroupsCompanion(
      id: Value(id),
      uuid: Value(uuid),
      name: Value(name),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
    );
  }

  factory HostGroup.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HostGroup(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  HostGroup copyWith({
    int? id,
    String? uuid,
    String? name,
    int? sortOrder,
    int? updatedAt,
  }) => HostGroup(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  HostGroup copyWithCompanion(HostGroupsCompanion data) {
    return HostGroup(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HostGroup(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, uuid, name, sortOrder, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HostGroup &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt);
}

class HostGroupsCompanion extends UpdateCompanion<HostGroup> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<int> updatedAt;
  const HostGroupsCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  HostGroupsCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String name,
    this.sortOrder = const Value.absent(),
    required int updatedAt,
  }) : uuid = Value(uuid),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<HostGroup> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  HostGroupsCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<int>? updatedAt,
  }) {
    return HostGroupsCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostGroupsCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $HostsTable extends Hosts with TableInfo<$HostsTable, Host> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HostsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _protocolMeta = const VerificationMeta(
    'protocol',
  );
  @override
  late final GeneratedColumn<String> protocol = GeneratedColumn<String>(
    'protocol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _groupUuidMeta = const VerificationMeta(
    'groupUuid',
  );
  @override
  late final GeneratedColumn<String> groupUuid = GeneratedColumn<String>(
    'group_uuid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _authTypeMeta = const VerificationMeta(
    'authType',
  );
  @override
  late final GeneratedColumn<String> authType = GeneratedColumn<String>(
    'auth_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('password'),
  );
  static const VerificationMeta _passwordEncMeta = const VerificationMeta(
    'passwordEnc',
  );
  @override
  late final GeneratedColumn<String> passwordEnc = GeneratedColumn<String>(
    'password_enc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _savePasswordMeta = const VerificationMeta(
    'savePassword',
  );
  @override
  late final GeneratedColumn<bool> savePassword = GeneratedColumn<bool>(
    'save_password',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("save_password" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _keyUuidMeta = const VerificationMeta(
    'keyUuid',
  );
  @override
  late final GeneratedColumn<String> keyUuid = GeneratedColumn<String>(
    'key_uuid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jumpChainMeta = const VerificationMeta(
    'jumpChain',
  );
  @override
  late final GeneratedColumn<String> jumpChain = GeneratedColumn<String>(
    'jump_chain',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _proxyTypeMeta = const VerificationMeta(
    'proxyType',
  );
  @override
  late final GeneratedColumn<String> proxyType = GeneratedColumn<String>(
    'proxy_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _proxyHostMeta = const VerificationMeta(
    'proxyHost',
  );
  @override
  late final GeneratedColumn<String> proxyHost = GeneratedColumn<String>(
    'proxy_host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _proxyPortMeta = const VerificationMeta(
    'proxyPort',
  );
  @override
  late final GeneratedColumn<int> proxyPort = GeneratedColumn<int>(
    'proxy_port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _proxyUserMeta = const VerificationMeta(
    'proxyUser',
  );
  @override
  late final GeneratedColumn<String> proxyUser = GeneratedColumn<String>(
    'proxy_user',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _proxyPassEncMeta = const VerificationMeta(
    'proxyPassEnc',
  );
  @override
  late final GeneratedColumn<String> proxyPassEnc = GeneratedColumn<String>(
    'proxy_pass_enc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _osIdMeta = const VerificationMeta('osId');
  @override
  late final GeneratedColumn<String> osId = GeneratedColumn<String>(
    'os_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _osNameMeta = const VerificationMeta('osName');
  @override
  late final GeneratedColumn<String> osName = GeneratedColumn<String>(
    'os_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hostKeyFingerprintMeta =
      const VerificationMeta('hostKeyFingerprint');
  @override
  late final GeneratedColumn<String> hostKeyFingerprint =
      GeneratedColumn<String>(
        'host_key_fingerprint',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _extraJsonMeta = const VerificationMeta(
    'extraJson',
  );
  @override
  late final GeneratedColumn<String> extraJson = GeneratedColumn<String>(
    'extra_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _syncEnabledMeta = const VerificationMeta(
    'syncEnabled',
  );
  @override
  late final GeneratedColumn<bool> syncEnabled = GeneratedColumn<bool>(
    'sync_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<int> syncedAt = GeneratedColumn<int>(
    'synced_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastConnectedAtMeta = const VerificationMeta(
    'lastConnectedAt',
  );
  @override
  late final GeneratedColumn<int> lastConnectedAt = GeneratedColumn<int>(
    'last_connected_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    protocol,
    name,
    groupUuid,
    address,
    port,
    username,
    authType,
    passwordEnc,
    savePassword,
    keyUuid,
    jumpChain,
    proxyType,
    proxyHost,
    proxyPort,
    proxyUser,
    proxyPassEnc,
    osId,
    osName,
    hostKeyFingerprint,
    extraJson,
    note,
    syncEnabled,
    syncedAt,
    updatedAt,
    createdAt,
    lastConnectedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hosts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Host> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('protocol')) {
      context.handle(
        _protocolMeta,
        protocol.isAcceptableOrUnknown(data['protocol']!, _protocolMeta),
      );
    } else if (isInserting) {
      context.missing(_protocolMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('group_uuid')) {
      context.handle(
        _groupUuidMeta,
        groupUuid.isAcceptableOrUnknown(data['group_uuid']!, _groupUuidMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('auth_type')) {
      context.handle(
        _authTypeMeta,
        authType.isAcceptableOrUnknown(data['auth_type']!, _authTypeMeta),
      );
    }
    if (data.containsKey('password_enc')) {
      context.handle(
        _passwordEncMeta,
        passwordEnc.isAcceptableOrUnknown(
          data['password_enc']!,
          _passwordEncMeta,
        ),
      );
    }
    if (data.containsKey('save_password')) {
      context.handle(
        _savePasswordMeta,
        savePassword.isAcceptableOrUnknown(
          data['save_password']!,
          _savePasswordMeta,
        ),
      );
    }
    if (data.containsKey('key_uuid')) {
      context.handle(
        _keyUuidMeta,
        keyUuid.isAcceptableOrUnknown(data['key_uuid']!, _keyUuidMeta),
      );
    }
    if (data.containsKey('jump_chain')) {
      context.handle(
        _jumpChainMeta,
        jumpChain.isAcceptableOrUnknown(data['jump_chain']!, _jumpChainMeta),
      );
    }
    if (data.containsKey('proxy_type')) {
      context.handle(
        _proxyTypeMeta,
        proxyType.isAcceptableOrUnknown(data['proxy_type']!, _proxyTypeMeta),
      );
    }
    if (data.containsKey('proxy_host')) {
      context.handle(
        _proxyHostMeta,
        proxyHost.isAcceptableOrUnknown(data['proxy_host']!, _proxyHostMeta),
      );
    }
    if (data.containsKey('proxy_port')) {
      context.handle(
        _proxyPortMeta,
        proxyPort.isAcceptableOrUnknown(data['proxy_port']!, _proxyPortMeta),
      );
    }
    if (data.containsKey('proxy_user')) {
      context.handle(
        _proxyUserMeta,
        proxyUser.isAcceptableOrUnknown(data['proxy_user']!, _proxyUserMeta),
      );
    }
    if (data.containsKey('proxy_pass_enc')) {
      context.handle(
        _proxyPassEncMeta,
        proxyPassEnc.isAcceptableOrUnknown(
          data['proxy_pass_enc']!,
          _proxyPassEncMeta,
        ),
      );
    }
    if (data.containsKey('os_id')) {
      context.handle(
        _osIdMeta,
        osId.isAcceptableOrUnknown(data['os_id']!, _osIdMeta),
      );
    }
    if (data.containsKey('os_name')) {
      context.handle(
        _osNameMeta,
        osName.isAcceptableOrUnknown(data['os_name']!, _osNameMeta),
      );
    }
    if (data.containsKey('host_key_fingerprint')) {
      context.handle(
        _hostKeyFingerprintMeta,
        hostKeyFingerprint.isAcceptableOrUnknown(
          data['host_key_fingerprint']!,
          _hostKeyFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('extra_json')) {
      context.handle(
        _extraJsonMeta,
        extraJson.isAcceptableOrUnknown(data['extra_json']!, _extraJsonMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('sync_enabled')) {
      context.handle(
        _syncEnabledMeta,
        syncEnabled.isAcceptableOrUnknown(
          data['sync_enabled']!,
          _syncEnabledMeta,
        ),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_connected_at')) {
      context.handle(
        _lastConnectedAtMeta,
        lastConnectedAt.isAcceptableOrUnknown(
          data['last_connected_at']!,
          _lastConnectedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Host map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Host(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      protocol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}protocol'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      groupUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_uuid'],
      ),
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      authType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_type'],
      )!,
      passwordEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_enc'],
      ),
      savePassword: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}save_password'],
      )!,
      keyUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_uuid'],
      ),
      jumpChain: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jump_chain'],
      )!,
      proxyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proxy_type'],
      )!,
      proxyHost: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proxy_host'],
      )!,
      proxyPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}proxy_port'],
      )!,
      proxyUser: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proxy_user'],
      )!,
      proxyPassEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proxy_pass_enc'],
      ),
      osId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}os_id'],
      ),
      osName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}os_name'],
      ),
      hostKeyFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_key_fingerprint'],
      ),
      extraJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra_json'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      syncEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_enabled'],
      )!,
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}synced_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      lastConnectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_connected_at'],
      ),
    );
  }

  @override
  $HostsTable createAlias(String alias) {
    return $HostsTable(attachedDatabase, alias);
  }
}

class Host extends DataClass implements Insertable<Host> {
  final int id;
  final String uuid;

  /// 协议：ssh / rdp / vnc
  final String protocol;
  final String name;
  final String? groupUuid;
  final String address;
  final int port;
  final String username;

  /// 认证方式：password / key / keyboard
  final String authType;
  final String? passwordEnc;
  final bool savePassword;
  final String? keyUuid;

  /// 跳板链：JSON 数组，元素为主机 uuid，按连接顺序排列
  final String jumpChain;

  /// 出口代理：none / http / socks5
  final String proxyType;
  final String proxyHost;
  final int proxyPort;
  final String proxyUser;
  final String? proxyPassEnc;

  /// 自动探测到的系统 id（如 ubuntu、rhel）与可读名称
  final String? osId;
  final String? osName;

  /// 首次连接记录的主机指纹（TOFU）
  final String? hostKeyFingerprint;
  final String extraJson;
  final String note;

  /// 是否参与同步，以及最后一次与服务器一致时的服务器更新时间
  final bool syncEnabled;
  final int? syncedAt;
  final int updatedAt;
  final int createdAt;
  final int? lastConnectedAt;
  const Host({
    required this.id,
    required this.uuid,
    required this.protocol,
    required this.name,
    this.groupUuid,
    required this.address,
    required this.port,
    required this.username,
    required this.authType,
    this.passwordEnc,
    required this.savePassword,
    this.keyUuid,
    required this.jumpChain,
    required this.proxyType,
    required this.proxyHost,
    required this.proxyPort,
    required this.proxyUser,
    this.proxyPassEnc,
    this.osId,
    this.osName,
    this.hostKeyFingerprint,
    required this.extraJson,
    required this.note,
    required this.syncEnabled,
    this.syncedAt,
    required this.updatedAt,
    required this.createdAt,
    this.lastConnectedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['protocol'] = Variable<String>(protocol);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || groupUuid != null) {
      map['group_uuid'] = Variable<String>(groupUuid);
    }
    map['address'] = Variable<String>(address);
    map['port'] = Variable<int>(port);
    map['username'] = Variable<String>(username);
    map['auth_type'] = Variable<String>(authType);
    if (!nullToAbsent || passwordEnc != null) {
      map['password_enc'] = Variable<String>(passwordEnc);
    }
    map['save_password'] = Variable<bool>(savePassword);
    if (!nullToAbsent || keyUuid != null) {
      map['key_uuid'] = Variable<String>(keyUuid);
    }
    map['jump_chain'] = Variable<String>(jumpChain);
    map['proxy_type'] = Variable<String>(proxyType);
    map['proxy_host'] = Variable<String>(proxyHost);
    map['proxy_port'] = Variable<int>(proxyPort);
    map['proxy_user'] = Variable<String>(proxyUser);
    if (!nullToAbsent || proxyPassEnc != null) {
      map['proxy_pass_enc'] = Variable<String>(proxyPassEnc);
    }
    if (!nullToAbsent || osId != null) {
      map['os_id'] = Variable<String>(osId);
    }
    if (!nullToAbsent || osName != null) {
      map['os_name'] = Variable<String>(osName);
    }
    if (!nullToAbsent || hostKeyFingerprint != null) {
      map['host_key_fingerprint'] = Variable<String>(hostKeyFingerprint);
    }
    map['extra_json'] = Variable<String>(extraJson);
    map['note'] = Variable<String>(note);
    map['sync_enabled'] = Variable<bool>(syncEnabled);
    if (!nullToAbsent || syncedAt != null) {
      map['synced_at'] = Variable<int>(syncedAt);
    }
    map['updated_at'] = Variable<int>(updatedAt);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || lastConnectedAt != null) {
      map['last_connected_at'] = Variable<int>(lastConnectedAt);
    }
    return map;
  }

  HostsCompanion toCompanion(bool nullToAbsent) {
    return HostsCompanion(
      id: Value(id),
      uuid: Value(uuid),
      protocol: Value(protocol),
      name: Value(name),
      groupUuid: groupUuid == null && nullToAbsent
          ? const Value.absent()
          : Value(groupUuid),
      address: Value(address),
      port: Value(port),
      username: Value(username),
      authType: Value(authType),
      passwordEnc: passwordEnc == null && nullToAbsent
          ? const Value.absent()
          : Value(passwordEnc),
      savePassword: Value(savePassword),
      keyUuid: keyUuid == null && nullToAbsent
          ? const Value.absent()
          : Value(keyUuid),
      jumpChain: Value(jumpChain),
      proxyType: Value(proxyType),
      proxyHost: Value(proxyHost),
      proxyPort: Value(proxyPort),
      proxyUser: Value(proxyUser),
      proxyPassEnc: proxyPassEnc == null && nullToAbsent
          ? const Value.absent()
          : Value(proxyPassEnc),
      osId: osId == null && nullToAbsent ? const Value.absent() : Value(osId),
      osName: osName == null && nullToAbsent
          ? const Value.absent()
          : Value(osName),
      hostKeyFingerprint: hostKeyFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(hostKeyFingerprint),
      extraJson: Value(extraJson),
      note: Value(note),
      syncEnabled: Value(syncEnabled),
      syncedAt: syncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedAt),
      updatedAt: Value(updatedAt),
      createdAt: Value(createdAt),
      lastConnectedAt: lastConnectedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastConnectedAt),
    );
  }

  factory Host.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Host(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      protocol: serializer.fromJson<String>(json['protocol']),
      name: serializer.fromJson<String>(json['name']),
      groupUuid: serializer.fromJson<String?>(json['groupUuid']),
      address: serializer.fromJson<String>(json['address']),
      port: serializer.fromJson<int>(json['port']),
      username: serializer.fromJson<String>(json['username']),
      authType: serializer.fromJson<String>(json['authType']),
      passwordEnc: serializer.fromJson<String?>(json['passwordEnc']),
      savePassword: serializer.fromJson<bool>(json['savePassword']),
      keyUuid: serializer.fromJson<String?>(json['keyUuid']),
      jumpChain: serializer.fromJson<String>(json['jumpChain']),
      proxyType: serializer.fromJson<String>(json['proxyType']),
      proxyHost: serializer.fromJson<String>(json['proxyHost']),
      proxyPort: serializer.fromJson<int>(json['proxyPort']),
      proxyUser: serializer.fromJson<String>(json['proxyUser']),
      proxyPassEnc: serializer.fromJson<String?>(json['proxyPassEnc']),
      osId: serializer.fromJson<String?>(json['osId']),
      osName: serializer.fromJson<String?>(json['osName']),
      hostKeyFingerprint: serializer.fromJson<String?>(
        json['hostKeyFingerprint'],
      ),
      extraJson: serializer.fromJson<String>(json['extraJson']),
      note: serializer.fromJson<String>(json['note']),
      syncEnabled: serializer.fromJson<bool>(json['syncEnabled']),
      syncedAt: serializer.fromJson<int?>(json['syncedAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastConnectedAt: serializer.fromJson<int?>(json['lastConnectedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'protocol': serializer.toJson<String>(protocol),
      'name': serializer.toJson<String>(name),
      'groupUuid': serializer.toJson<String?>(groupUuid),
      'address': serializer.toJson<String>(address),
      'port': serializer.toJson<int>(port),
      'username': serializer.toJson<String>(username),
      'authType': serializer.toJson<String>(authType),
      'passwordEnc': serializer.toJson<String?>(passwordEnc),
      'savePassword': serializer.toJson<bool>(savePassword),
      'keyUuid': serializer.toJson<String?>(keyUuid),
      'jumpChain': serializer.toJson<String>(jumpChain),
      'proxyType': serializer.toJson<String>(proxyType),
      'proxyHost': serializer.toJson<String>(proxyHost),
      'proxyPort': serializer.toJson<int>(proxyPort),
      'proxyUser': serializer.toJson<String>(proxyUser),
      'proxyPassEnc': serializer.toJson<String?>(proxyPassEnc),
      'osId': serializer.toJson<String?>(osId),
      'osName': serializer.toJson<String?>(osName),
      'hostKeyFingerprint': serializer.toJson<String?>(hostKeyFingerprint),
      'extraJson': serializer.toJson<String>(extraJson),
      'note': serializer.toJson<String>(note),
      'syncEnabled': serializer.toJson<bool>(syncEnabled),
      'syncedAt': serializer.toJson<int?>(syncedAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastConnectedAt': serializer.toJson<int?>(lastConnectedAt),
    };
  }

  Host copyWith({
    int? id,
    String? uuid,
    String? protocol,
    String? name,
    Value<String?> groupUuid = const Value.absent(),
    String? address,
    int? port,
    String? username,
    String? authType,
    Value<String?> passwordEnc = const Value.absent(),
    bool? savePassword,
    Value<String?> keyUuid = const Value.absent(),
    String? jumpChain,
    String? proxyType,
    String? proxyHost,
    int? proxyPort,
    String? proxyUser,
    Value<String?> proxyPassEnc = const Value.absent(),
    Value<String?> osId = const Value.absent(),
    Value<String?> osName = const Value.absent(),
    Value<String?> hostKeyFingerprint = const Value.absent(),
    String? extraJson,
    String? note,
    bool? syncEnabled,
    Value<int?> syncedAt = const Value.absent(),
    int? updatedAt,
    int? createdAt,
    Value<int?> lastConnectedAt = const Value.absent(),
  }) => Host(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    protocol: protocol ?? this.protocol,
    name: name ?? this.name,
    groupUuid: groupUuid.present ? groupUuid.value : this.groupUuid,
    address: address ?? this.address,
    port: port ?? this.port,
    username: username ?? this.username,
    authType: authType ?? this.authType,
    passwordEnc: passwordEnc.present ? passwordEnc.value : this.passwordEnc,
    savePassword: savePassword ?? this.savePassword,
    keyUuid: keyUuid.present ? keyUuid.value : this.keyUuid,
    jumpChain: jumpChain ?? this.jumpChain,
    proxyType: proxyType ?? this.proxyType,
    proxyHost: proxyHost ?? this.proxyHost,
    proxyPort: proxyPort ?? this.proxyPort,
    proxyUser: proxyUser ?? this.proxyUser,
    proxyPassEnc: proxyPassEnc.present ? proxyPassEnc.value : this.proxyPassEnc,
    osId: osId.present ? osId.value : this.osId,
    osName: osName.present ? osName.value : this.osName,
    hostKeyFingerprint: hostKeyFingerprint.present
        ? hostKeyFingerprint.value
        : this.hostKeyFingerprint,
    extraJson: extraJson ?? this.extraJson,
    note: note ?? this.note,
    syncEnabled: syncEnabled ?? this.syncEnabled,
    syncedAt: syncedAt.present ? syncedAt.value : this.syncedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    createdAt: createdAt ?? this.createdAt,
    lastConnectedAt: lastConnectedAt.present
        ? lastConnectedAt.value
        : this.lastConnectedAt,
  );
  Host copyWithCompanion(HostsCompanion data) {
    return Host(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      name: data.name.present ? data.name.value : this.name,
      groupUuid: data.groupUuid.present ? data.groupUuid.value : this.groupUuid,
      address: data.address.present ? data.address.value : this.address,
      port: data.port.present ? data.port.value : this.port,
      username: data.username.present ? data.username.value : this.username,
      authType: data.authType.present ? data.authType.value : this.authType,
      passwordEnc: data.passwordEnc.present
          ? data.passwordEnc.value
          : this.passwordEnc,
      savePassword: data.savePassword.present
          ? data.savePassword.value
          : this.savePassword,
      keyUuid: data.keyUuid.present ? data.keyUuid.value : this.keyUuid,
      jumpChain: data.jumpChain.present ? data.jumpChain.value : this.jumpChain,
      proxyType: data.proxyType.present ? data.proxyType.value : this.proxyType,
      proxyHost: data.proxyHost.present ? data.proxyHost.value : this.proxyHost,
      proxyPort: data.proxyPort.present ? data.proxyPort.value : this.proxyPort,
      proxyUser: data.proxyUser.present ? data.proxyUser.value : this.proxyUser,
      proxyPassEnc: data.proxyPassEnc.present
          ? data.proxyPassEnc.value
          : this.proxyPassEnc,
      osId: data.osId.present ? data.osId.value : this.osId,
      osName: data.osName.present ? data.osName.value : this.osName,
      hostKeyFingerprint: data.hostKeyFingerprint.present
          ? data.hostKeyFingerprint.value
          : this.hostKeyFingerprint,
      extraJson: data.extraJson.present ? data.extraJson.value : this.extraJson,
      note: data.note.present ? data.note.value : this.note,
      syncEnabled: data.syncEnabled.present
          ? data.syncEnabled.value
          : this.syncEnabled,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastConnectedAt: data.lastConnectedAt.present
          ? data.lastConnectedAt.value
          : this.lastConnectedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Host(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('protocol: $protocol, ')
          ..write('name: $name, ')
          ..write('groupUuid: $groupUuid, ')
          ..write('address: $address, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('authType: $authType, ')
          ..write('passwordEnc: $passwordEnc, ')
          ..write('savePassword: $savePassword, ')
          ..write('keyUuid: $keyUuid, ')
          ..write('jumpChain: $jumpChain, ')
          ..write('proxyType: $proxyType, ')
          ..write('proxyHost: $proxyHost, ')
          ..write('proxyPort: $proxyPort, ')
          ..write('proxyUser: $proxyUser, ')
          ..write('proxyPassEnc: $proxyPassEnc, ')
          ..write('osId: $osId, ')
          ..write('osName: $osName, ')
          ..write('hostKeyFingerprint: $hostKeyFingerprint, ')
          ..write('extraJson: $extraJson, ')
          ..write('note: $note, ')
          ..write('syncEnabled: $syncEnabled, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastConnectedAt: $lastConnectedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    uuid,
    protocol,
    name,
    groupUuid,
    address,
    port,
    username,
    authType,
    passwordEnc,
    savePassword,
    keyUuid,
    jumpChain,
    proxyType,
    proxyHost,
    proxyPort,
    proxyUser,
    proxyPassEnc,
    osId,
    osName,
    hostKeyFingerprint,
    extraJson,
    note,
    syncEnabled,
    syncedAt,
    updatedAt,
    createdAt,
    lastConnectedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Host &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.protocol == this.protocol &&
          other.name == this.name &&
          other.groupUuid == this.groupUuid &&
          other.address == this.address &&
          other.port == this.port &&
          other.username == this.username &&
          other.authType == this.authType &&
          other.passwordEnc == this.passwordEnc &&
          other.savePassword == this.savePassword &&
          other.keyUuid == this.keyUuid &&
          other.jumpChain == this.jumpChain &&
          other.proxyType == this.proxyType &&
          other.proxyHost == this.proxyHost &&
          other.proxyPort == this.proxyPort &&
          other.proxyUser == this.proxyUser &&
          other.proxyPassEnc == this.proxyPassEnc &&
          other.osId == this.osId &&
          other.osName == this.osName &&
          other.hostKeyFingerprint == this.hostKeyFingerprint &&
          other.extraJson == this.extraJson &&
          other.note == this.note &&
          other.syncEnabled == this.syncEnabled &&
          other.syncedAt == this.syncedAt &&
          other.updatedAt == this.updatedAt &&
          other.createdAt == this.createdAt &&
          other.lastConnectedAt == this.lastConnectedAt);
}

class HostsCompanion extends UpdateCompanion<Host> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> protocol;
  final Value<String> name;
  final Value<String?> groupUuid;
  final Value<String> address;
  final Value<int> port;
  final Value<String> username;
  final Value<String> authType;
  final Value<String?> passwordEnc;
  final Value<bool> savePassword;
  final Value<String?> keyUuid;
  final Value<String> jumpChain;
  final Value<String> proxyType;
  final Value<String> proxyHost;
  final Value<int> proxyPort;
  final Value<String> proxyUser;
  final Value<String?> proxyPassEnc;
  final Value<String?> osId;
  final Value<String?> osName;
  final Value<String?> hostKeyFingerprint;
  final Value<String> extraJson;
  final Value<String> note;
  final Value<bool> syncEnabled;
  final Value<int?> syncedAt;
  final Value<int> updatedAt;
  final Value<int> createdAt;
  final Value<int?> lastConnectedAt;
  const HostsCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.protocol = const Value.absent(),
    this.name = const Value.absent(),
    this.groupUuid = const Value.absent(),
    this.address = const Value.absent(),
    this.port = const Value.absent(),
    this.username = const Value.absent(),
    this.authType = const Value.absent(),
    this.passwordEnc = const Value.absent(),
    this.savePassword = const Value.absent(),
    this.keyUuid = const Value.absent(),
    this.jumpChain = const Value.absent(),
    this.proxyType = const Value.absent(),
    this.proxyHost = const Value.absent(),
    this.proxyPort = const Value.absent(),
    this.proxyUser = const Value.absent(),
    this.proxyPassEnc = const Value.absent(),
    this.osId = const Value.absent(),
    this.osName = const Value.absent(),
    this.hostKeyFingerprint = const Value.absent(),
    this.extraJson = const Value.absent(),
    this.note = const Value.absent(),
    this.syncEnabled = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
  });
  HostsCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String protocol,
    required String name,
    this.groupUuid = const Value.absent(),
    required String address,
    required int port,
    this.username = const Value.absent(),
    this.authType = const Value.absent(),
    this.passwordEnc = const Value.absent(),
    this.savePassword = const Value.absent(),
    this.keyUuid = const Value.absent(),
    this.jumpChain = const Value.absent(),
    this.proxyType = const Value.absent(),
    this.proxyHost = const Value.absent(),
    this.proxyPort = const Value.absent(),
    this.proxyUser = const Value.absent(),
    this.proxyPassEnc = const Value.absent(),
    this.osId = const Value.absent(),
    this.osName = const Value.absent(),
    this.hostKeyFingerprint = const Value.absent(),
    this.extraJson = const Value.absent(),
    this.note = const Value.absent(),
    this.syncEnabled = const Value.absent(),
    this.syncedAt = const Value.absent(),
    required int updatedAt,
    required int createdAt,
    this.lastConnectedAt = const Value.absent(),
  }) : uuid = Value(uuid),
       protocol = Value(protocol),
       name = Value(name),
       address = Value(address),
       port = Value(port),
       updatedAt = Value(updatedAt),
       createdAt = Value(createdAt);
  static Insertable<Host> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? protocol,
    Expression<String>? name,
    Expression<String>? groupUuid,
    Expression<String>? address,
    Expression<int>? port,
    Expression<String>? username,
    Expression<String>? authType,
    Expression<String>? passwordEnc,
    Expression<bool>? savePassword,
    Expression<String>? keyUuid,
    Expression<String>? jumpChain,
    Expression<String>? proxyType,
    Expression<String>? proxyHost,
    Expression<int>? proxyPort,
    Expression<String>? proxyUser,
    Expression<String>? proxyPassEnc,
    Expression<String>? osId,
    Expression<String>? osName,
    Expression<String>? hostKeyFingerprint,
    Expression<String>? extraJson,
    Expression<String>? note,
    Expression<bool>? syncEnabled,
    Expression<int>? syncedAt,
    Expression<int>? updatedAt,
    Expression<int>? createdAt,
    Expression<int>? lastConnectedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (protocol != null) 'protocol': protocol,
      if (name != null) 'name': name,
      if (groupUuid != null) 'group_uuid': groupUuid,
      if (address != null) 'address': address,
      if (port != null) 'port': port,
      if (username != null) 'username': username,
      if (authType != null) 'auth_type': authType,
      if (passwordEnc != null) 'password_enc': passwordEnc,
      if (savePassword != null) 'save_password': savePassword,
      if (keyUuid != null) 'key_uuid': keyUuid,
      if (jumpChain != null) 'jump_chain': jumpChain,
      if (proxyType != null) 'proxy_type': proxyType,
      if (proxyHost != null) 'proxy_host': proxyHost,
      if (proxyPort != null) 'proxy_port': proxyPort,
      if (proxyUser != null) 'proxy_user': proxyUser,
      if (proxyPassEnc != null) 'proxy_pass_enc': proxyPassEnc,
      if (osId != null) 'os_id': osId,
      if (osName != null) 'os_name': osName,
      if (hostKeyFingerprint != null)
        'host_key_fingerprint': hostKeyFingerprint,
      if (extraJson != null) 'extra_json': extraJson,
      if (note != null) 'note': note,
      if (syncEnabled != null) 'sync_enabled': syncEnabled,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
    });
  }

  HostsCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? protocol,
    Value<String>? name,
    Value<String?>? groupUuid,
    Value<String>? address,
    Value<int>? port,
    Value<String>? username,
    Value<String>? authType,
    Value<String?>? passwordEnc,
    Value<bool>? savePassword,
    Value<String?>? keyUuid,
    Value<String>? jumpChain,
    Value<String>? proxyType,
    Value<String>? proxyHost,
    Value<int>? proxyPort,
    Value<String>? proxyUser,
    Value<String?>? proxyPassEnc,
    Value<String?>? osId,
    Value<String?>? osName,
    Value<String?>? hostKeyFingerprint,
    Value<String>? extraJson,
    Value<String>? note,
    Value<bool>? syncEnabled,
    Value<int?>? syncedAt,
    Value<int>? updatedAt,
    Value<int>? createdAt,
    Value<int?>? lastConnectedAt,
  }) {
    return HostsCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      protocol: protocol ?? this.protocol,
      name: name ?? this.name,
      groupUuid: groupUuid ?? this.groupUuid,
      address: address ?? this.address,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      passwordEnc: passwordEnc ?? this.passwordEnc,
      savePassword: savePassword ?? this.savePassword,
      keyUuid: keyUuid ?? this.keyUuid,
      jumpChain: jumpChain ?? this.jumpChain,
      proxyType: proxyType ?? this.proxyType,
      proxyHost: proxyHost ?? this.proxyHost,
      proxyPort: proxyPort ?? this.proxyPort,
      proxyUser: proxyUser ?? this.proxyUser,
      proxyPassEnc: proxyPassEnc ?? this.proxyPassEnc,
      osId: osId ?? this.osId,
      osName: osName ?? this.osName,
      hostKeyFingerprint: hostKeyFingerprint ?? this.hostKeyFingerprint,
      extraJson: extraJson ?? this.extraJson,
      note: note ?? this.note,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncedAt: syncedAt ?? this.syncedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(protocol.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (groupUuid.present) {
      map['group_uuid'] = Variable<String>(groupUuid.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (authType.present) {
      map['auth_type'] = Variable<String>(authType.value);
    }
    if (passwordEnc.present) {
      map['password_enc'] = Variable<String>(passwordEnc.value);
    }
    if (savePassword.present) {
      map['save_password'] = Variable<bool>(savePassword.value);
    }
    if (keyUuid.present) {
      map['key_uuid'] = Variable<String>(keyUuid.value);
    }
    if (jumpChain.present) {
      map['jump_chain'] = Variable<String>(jumpChain.value);
    }
    if (proxyType.present) {
      map['proxy_type'] = Variable<String>(proxyType.value);
    }
    if (proxyHost.present) {
      map['proxy_host'] = Variable<String>(proxyHost.value);
    }
    if (proxyPort.present) {
      map['proxy_port'] = Variable<int>(proxyPort.value);
    }
    if (proxyUser.present) {
      map['proxy_user'] = Variable<String>(proxyUser.value);
    }
    if (proxyPassEnc.present) {
      map['proxy_pass_enc'] = Variable<String>(proxyPassEnc.value);
    }
    if (osId.present) {
      map['os_id'] = Variable<String>(osId.value);
    }
    if (osName.present) {
      map['os_name'] = Variable<String>(osName.value);
    }
    if (hostKeyFingerprint.present) {
      map['host_key_fingerprint'] = Variable<String>(hostKeyFingerprint.value);
    }
    if (extraJson.present) {
      map['extra_json'] = Variable<String>(extraJson.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (syncEnabled.present) {
      map['sync_enabled'] = Variable<bool>(syncEnabled.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<int>(syncedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastConnectedAt.present) {
      map['last_connected_at'] = Variable<int>(lastConnectedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HostsCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('protocol: $protocol, ')
          ..write('name: $name, ')
          ..write('groupUuid: $groupUuid, ')
          ..write('address: $address, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('authType: $authType, ')
          ..write('passwordEnc: $passwordEnc, ')
          ..write('savePassword: $savePassword, ')
          ..write('keyUuid: $keyUuid, ')
          ..write('jumpChain: $jumpChain, ')
          ..write('proxyType: $proxyType, ')
          ..write('proxyHost: $proxyHost, ')
          ..write('proxyPort: $proxyPort, ')
          ..write('proxyUser: $proxyUser, ')
          ..write('proxyPassEnc: $proxyPassEnc, ')
          ..write('osId: $osId, ')
          ..write('osName: $osName, ')
          ..write('hostKeyFingerprint: $hostKeyFingerprint, ')
          ..write('extraJson: $extraJson, ')
          ..write('note: $note, ')
          ..write('syncEnabled: $syncEnabled, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastConnectedAt: $lastConnectedAt')
          ..write(')'))
        .toString();
  }
}

class $SshKeysTable extends SshKeys with TableInfo<$SshKeysTable, SshKey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SshKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyTypeMeta = const VerificationMeta(
    'keyType',
  );
  @override
  late final GeneratedColumn<String> keyType = GeneratedColumn<String>(
    'key_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _privateKeyEncMeta = const VerificationMeta(
    'privateKeyEnc',
  );
  @override
  late final GeneratedColumn<String> privateKeyEnc = GeneratedColumn<String>(
    'private_key_enc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passphraseEncMeta = const VerificationMeta(
    'passphraseEnc',
  );
  @override
  late final GeneratedColumn<String> passphraseEnc = GeneratedColumn<String>(
    'passphrase_enc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    name,
    keyType,
    privateKeyEnc,
    passphraseEnc,
    publicKey,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ssh_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<SshKey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('key_type')) {
      context.handle(
        _keyTypeMeta,
        keyType.isAcceptableOrUnknown(data['key_type']!, _keyTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_keyTypeMeta);
    }
    if (data.containsKey('private_key_enc')) {
      context.handle(
        _privateKeyEncMeta,
        privateKeyEnc.isAcceptableOrUnknown(
          data['private_key_enc']!,
          _privateKeyEncMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_privateKeyEncMeta);
    }
    if (data.containsKey('passphrase_enc')) {
      context.handle(
        _passphraseEncMeta,
        passphraseEnc.isAcceptableOrUnknown(
          data['passphrase_enc']!,
          _passphraseEncMeta,
        ),
      );
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SshKey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SshKey(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      keyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_type'],
      )!,
      privateKeyEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}private_key_enc'],
      )!,
      passphraseEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}passphrase_enc'],
      ),
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SshKeysTable createAlias(String alias) {
    return $SshKeysTable(attachedDatabase, alias);
  }
}

class SshKey extends DataClass implements Insertable<SshKey> {
  final int id;
  final String uuid;
  final String name;
  final String keyType;
  final String privateKeyEnc;
  final String? passphraseEnc;
  final String publicKey;
  final int createdAt;
  final int updatedAt;
  const SshKey({
    required this.id,
    required this.uuid,
    required this.name,
    required this.keyType,
    required this.privateKeyEnc,
    this.passphraseEnc,
    required this.publicKey,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['name'] = Variable<String>(name);
    map['key_type'] = Variable<String>(keyType);
    map['private_key_enc'] = Variable<String>(privateKeyEnc);
    if (!nullToAbsent || passphraseEnc != null) {
      map['passphrase_enc'] = Variable<String>(passphraseEnc);
    }
    map['public_key'] = Variable<String>(publicKey);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SshKeysCompanion toCompanion(bool nullToAbsent) {
    return SshKeysCompanion(
      id: Value(id),
      uuid: Value(uuid),
      name: Value(name),
      keyType: Value(keyType),
      privateKeyEnc: Value(privateKeyEnc),
      passphraseEnc: passphraseEnc == null && nullToAbsent
          ? const Value.absent()
          : Value(passphraseEnc),
      publicKey: Value(publicKey),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SshKey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SshKey(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      name: serializer.fromJson<String>(json['name']),
      keyType: serializer.fromJson<String>(json['keyType']),
      privateKeyEnc: serializer.fromJson<String>(json['privateKeyEnc']),
      passphraseEnc: serializer.fromJson<String?>(json['passphraseEnc']),
      publicKey: serializer.fromJson<String>(json['publicKey']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'name': serializer.toJson<String>(name),
      'keyType': serializer.toJson<String>(keyType),
      'privateKeyEnc': serializer.toJson<String>(privateKeyEnc),
      'passphraseEnc': serializer.toJson<String?>(passphraseEnc),
      'publicKey': serializer.toJson<String>(publicKey),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SshKey copyWith({
    int? id,
    String? uuid,
    String? name,
    String? keyType,
    String? privateKeyEnc,
    Value<String?> passphraseEnc = const Value.absent(),
    String? publicKey,
    int? createdAt,
    int? updatedAt,
  }) => SshKey(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    name: name ?? this.name,
    keyType: keyType ?? this.keyType,
    privateKeyEnc: privateKeyEnc ?? this.privateKeyEnc,
    passphraseEnc: passphraseEnc.present
        ? passphraseEnc.value
        : this.passphraseEnc,
    publicKey: publicKey ?? this.publicKey,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SshKey copyWithCompanion(SshKeysCompanion data) {
    return SshKey(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      name: data.name.present ? data.name.value : this.name,
      keyType: data.keyType.present ? data.keyType.value : this.keyType,
      privateKeyEnc: data.privateKeyEnc.present
          ? data.privateKeyEnc.value
          : this.privateKeyEnc,
      passphraseEnc: data.passphraseEnc.present
          ? data.passphraseEnc.value
          : this.passphraseEnc,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SshKey(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('keyType: $keyType, ')
          ..write('privateKeyEnc: $privateKeyEnc, ')
          ..write('passphraseEnc: $passphraseEnc, ')
          ..write('publicKey: $publicKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uuid,
    name,
    keyType,
    privateKeyEnc,
    passphraseEnc,
    publicKey,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SshKey &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.name == this.name &&
          other.keyType == this.keyType &&
          other.privateKeyEnc == this.privateKeyEnc &&
          other.passphraseEnc == this.passphraseEnc &&
          other.publicKey == this.publicKey &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SshKeysCompanion extends UpdateCompanion<SshKey> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> name;
  final Value<String> keyType;
  final Value<String> privateKeyEnc;
  final Value<String?> passphraseEnc;
  final Value<String> publicKey;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const SshKeysCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.name = const Value.absent(),
    this.keyType = const Value.absent(),
    this.privateKeyEnc = const Value.absent(),
    this.passphraseEnc = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SshKeysCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String name,
    required String keyType,
    required String privateKeyEnc,
    this.passphraseEnc = const Value.absent(),
    this.publicKey = const Value.absent(),
    required int createdAt,
    required int updatedAt,
  }) : uuid = Value(uuid),
       name = Value(name),
       keyType = Value(keyType),
       privateKeyEnc = Value(privateKeyEnc),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SshKey> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? name,
    Expression<String>? keyType,
    Expression<String>? privateKeyEnc,
    Expression<String>? passphraseEnc,
    Expression<String>? publicKey,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (name != null) 'name': name,
      if (keyType != null) 'key_type': keyType,
      if (privateKeyEnc != null) 'private_key_enc': privateKeyEnc,
      if (passphraseEnc != null) 'passphrase_enc': passphraseEnc,
      if (publicKey != null) 'public_key': publicKey,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SshKeysCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? name,
    Value<String>? keyType,
    Value<String>? privateKeyEnc,
    Value<String?>? passphraseEnc,
    Value<String>? publicKey,
    Value<int>? createdAt,
    Value<int>? updatedAt,
  }) {
    return SshKeysCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      keyType: keyType ?? this.keyType,
      privateKeyEnc: privateKeyEnc ?? this.privateKeyEnc,
      passphraseEnc: passphraseEnc ?? this.passphraseEnc,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (keyType.present) {
      map['key_type'] = Variable<String>(keyType.value);
    }
    if (privateKeyEnc.present) {
      map['private_key_enc'] = Variable<String>(privateKeyEnc.value);
    }
    if (passphraseEnc.present) {
      map['passphrase_enc'] = Variable<String>(passphraseEnc.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SshKeysCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('keyType: $keyType, ')
          ..write('privateKeyEnc: $privateKeyEnc, ')
          ..write('passphraseEnc: $passphraseEnc, ')
          ..write('publicKey: $publicKey, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $SnippetsTable extends Snippets with TableInfo<$SnippetsTable, Snippet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SnippetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _autoEnterMeta = const VerificationMeta(
    'autoEnter',
  );
  @override
  late final GeneratedColumn<bool> autoEnter = GeneratedColumn<bool>(
    'auto_enter',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_enter" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    name,
    content,
    kind,
    autoEnter,
    sortOrder,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'snippets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Snippet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('auto_enter')) {
      context.handle(
        _autoEnterMeta,
        autoEnter.isAcceptableOrUnknown(data['auto_enter']!, _autoEnterMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Snippet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Snippet(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      autoEnter: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_enter'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SnippetsTable createAlias(String alias) {
    return $SnippetsTable(attachedDatabase, alias);
  }
}

class Snippet extends DataClass implements Insertable<Snippet> {
  final int id;
  final String uuid;
  final String name;
  final String content;

  /// 类型：text（普通字符串）/ install_system_key（系统免密登录动作）
  final String kind;

  /// 是否在发送后自动回车
  final bool autoEnter;
  final int sortOrder;
  final int updatedAt;
  const Snippet({
    required this.id,
    required this.uuid,
    required this.name,
    required this.content,
    required this.kind,
    required this.autoEnter,
    required this.sortOrder,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['name'] = Variable<String>(name);
    map['content'] = Variable<String>(content);
    map['kind'] = Variable<String>(kind);
    map['auto_enter'] = Variable<bool>(autoEnter);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SnippetsCompanion toCompanion(bool nullToAbsent) {
    return SnippetsCompanion(
      id: Value(id),
      uuid: Value(uuid),
      name: Value(name),
      content: Value(content),
      kind: Value(kind),
      autoEnter: Value(autoEnter),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
    );
  }

  factory Snippet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Snippet(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      name: serializer.fromJson<String>(json['name']),
      content: serializer.fromJson<String>(json['content']),
      kind: serializer.fromJson<String>(json['kind']),
      autoEnter: serializer.fromJson<bool>(json['autoEnter']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'name': serializer.toJson<String>(name),
      'content': serializer.toJson<String>(content),
      'kind': serializer.toJson<String>(kind),
      'autoEnter': serializer.toJson<bool>(autoEnter),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Snippet copyWith({
    int? id,
    String? uuid,
    String? name,
    String? content,
    String? kind,
    bool? autoEnter,
    int? sortOrder,
    int? updatedAt,
  }) => Snippet(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    name: name ?? this.name,
    content: content ?? this.content,
    kind: kind ?? this.kind,
    autoEnter: autoEnter ?? this.autoEnter,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Snippet copyWithCompanion(SnippetsCompanion data) {
    return Snippet(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      name: data.name.present ? data.name.value : this.name,
      content: data.content.present ? data.content.value : this.content,
      kind: data.kind.present ? data.kind.value : this.kind,
      autoEnter: data.autoEnter.present ? data.autoEnter.value : this.autoEnter,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Snippet(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('content: $content, ')
          ..write('kind: $kind, ')
          ..write('autoEnter: $autoEnter, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uuid,
    name,
    content,
    kind,
    autoEnter,
    sortOrder,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Snippet &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.name == this.name &&
          other.content == this.content &&
          other.kind == this.kind &&
          other.autoEnter == this.autoEnter &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt);
}

class SnippetsCompanion extends UpdateCompanion<Snippet> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> name;
  final Value<String> content;
  final Value<String> kind;
  final Value<bool> autoEnter;
  final Value<int> sortOrder;
  final Value<int> updatedAt;
  const SnippetsCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.name = const Value.absent(),
    this.content = const Value.absent(),
    this.kind = const Value.absent(),
    this.autoEnter = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SnippetsCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String name,
    this.content = const Value.absent(),
    this.kind = const Value.absent(),
    this.autoEnter = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required int updatedAt,
  }) : uuid = Value(uuid),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<Snippet> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? name,
    Expression<String>? content,
    Expression<String>? kind,
    Expression<bool>? autoEnter,
    Expression<int>? sortOrder,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (name != null) 'name': name,
      if (content != null) 'content': content,
      if (kind != null) 'kind': kind,
      if (autoEnter != null) 'auto_enter': autoEnter,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SnippetsCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? name,
    Value<String>? content,
    Value<String>? kind,
    Value<bool>? autoEnter,
    Value<int>? sortOrder,
    Value<int>? updatedAt,
  }) {
    return SnippetsCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      content: content ?? this.content,
      kind: kind ?? this.kind,
      autoEnter: autoEnter ?? this.autoEnter,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (autoEnter.present) {
      map['auto_enter'] = Variable<bool>(autoEnter.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SnippetsCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('content: $content, ')
          ..write('kind: $kind, ')
          ..write('autoEnter: $autoEnter, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AgentConfigsTable extends AgentConfigs
    with TableInfo<$AgentConfigsTable, AgentConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AgentConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandMeta = const VerificationMeta(
    'command',
  );
  @override
  late final GeneratedColumn<String> command = GeneratedColumn<String>(
    'command',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _argsMeta = const VerificationMeta('args');
  @override
  late final GeneratedColumn<String> args = GeneratedColumn<String>(
    'args',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _endpointMeta = const VerificationMeta(
    'endpoint',
  );
  @override
  late final GeneratedColumn<String> endpoint = GeneratedColumn<String>(
    'endpoint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _apiKeyEncMeta = const VerificationMeta(
    'apiKeyEnc',
  );
  @override
  late final GeneratedColumn<String> apiKeyEnc = GeneratedColumn<String>(
    'api_key_enc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _systemPromptMeta = const VerificationMeta(
    'systemPrompt',
  );
  @override
  late final GeneratedColumn<String> systemPrompt = GeneratedColumn<String>(
    'system_prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasoningEffortMeta = const VerificationMeta(
    'reasoningEffort',
  );
  @override
  late final GeneratedColumn<String> reasoningEffort = GeneratedColumn<String>(
    'reasoning_effort',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    name,
    kind,
    command,
    args,
    endpoint,
    apiKeyEnc,
    model,
    systemPrompt,
    isActive,
    createdAt,
    reasoningEffort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'agent_configs';
  @override
  VerificationContext validateIntegrity(
    Insertable<AgentConfig> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('command')) {
      context.handle(
        _commandMeta,
        command.isAcceptableOrUnknown(data['command']!, _commandMeta),
      );
    }
    if (data.containsKey('args')) {
      context.handle(
        _argsMeta,
        args.isAcceptableOrUnknown(data['args']!, _argsMeta),
      );
    }
    if (data.containsKey('endpoint')) {
      context.handle(
        _endpointMeta,
        endpoint.isAcceptableOrUnknown(data['endpoint']!, _endpointMeta),
      );
    }
    if (data.containsKey('api_key_enc')) {
      context.handle(
        _apiKeyEncMeta,
        apiKeyEnc.isAcceptableOrUnknown(data['api_key_enc']!, _apiKeyEncMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('system_prompt')) {
      context.handle(
        _systemPromptMeta,
        systemPrompt.isAcceptableOrUnknown(
          data['system_prompt']!,
          _systemPromptMeta,
        ),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('reasoning_effort')) {
      context.handle(
        _reasoningEffortMeta,
        reasoningEffort.isAcceptableOrUnknown(
          data['reasoning_effort']!,
          _reasoningEffortMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AgentConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AgentConfig(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      command: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command'],
      )!,
      args: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}args'],
      )!,
      endpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endpoint'],
      )!,
      apiKeyEnc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}api_key_enc'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      systemPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}system_prompt'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      reasoningEffort: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reasoning_effort'],
      )!,
    );
  }

  @override
  $AgentConfigsTable createAlias(String alias) {
    return $AgentConfigsTable(attachedDatabase, alias);
  }
}

class AgentConfig extends DataClass implements Insertable<AgentConfig> {
  final int id;
  final String uuid;
  final String name;

  /// 实现类型：deepseek_cli / openai_api / codex
  final String kind;
  final String command;
  final String args;
  final String endpoint;
  final String? apiKeyEnc;
  final String model;
  final String systemPrompt;
  final bool isActive;
  final int createdAt;

  /// 推理强度（Codex：low / medium / high 等），空字符串为模型默认（schema 2 新增）
  final String reasoningEffort;
  const AgentConfig({
    required this.id,
    required this.uuid,
    required this.name,
    required this.kind,
    required this.command,
    required this.args,
    required this.endpoint,
    this.apiKeyEnc,
    required this.model,
    required this.systemPrompt,
    required this.isActive,
    required this.createdAt,
    required this.reasoningEffort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['command'] = Variable<String>(command);
    map['args'] = Variable<String>(args);
    map['endpoint'] = Variable<String>(endpoint);
    if (!nullToAbsent || apiKeyEnc != null) {
      map['api_key_enc'] = Variable<String>(apiKeyEnc);
    }
    map['model'] = Variable<String>(model);
    map['system_prompt'] = Variable<String>(systemPrompt);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<int>(createdAt);
    map['reasoning_effort'] = Variable<String>(reasoningEffort);
    return map;
  }

  AgentConfigsCompanion toCompanion(bool nullToAbsent) {
    return AgentConfigsCompanion(
      id: Value(id),
      uuid: Value(uuid),
      name: Value(name),
      kind: Value(kind),
      command: Value(command),
      args: Value(args),
      endpoint: Value(endpoint),
      apiKeyEnc: apiKeyEnc == null && nullToAbsent
          ? const Value.absent()
          : Value(apiKeyEnc),
      model: Value(model),
      systemPrompt: Value(systemPrompt),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      reasoningEffort: Value(reasoningEffort),
    );
  }

  factory AgentConfig.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AgentConfig(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      command: serializer.fromJson<String>(json['command']),
      args: serializer.fromJson<String>(json['args']),
      endpoint: serializer.fromJson<String>(json['endpoint']),
      apiKeyEnc: serializer.fromJson<String?>(json['apiKeyEnc']),
      model: serializer.fromJson<String>(json['model']),
      systemPrompt: serializer.fromJson<String>(json['systemPrompt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      reasoningEffort: serializer.fromJson<String>(json['reasoningEffort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'command': serializer.toJson<String>(command),
      'args': serializer.toJson<String>(args),
      'endpoint': serializer.toJson<String>(endpoint),
      'apiKeyEnc': serializer.toJson<String?>(apiKeyEnc),
      'model': serializer.toJson<String>(model),
      'systemPrompt': serializer.toJson<String>(systemPrompt),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<int>(createdAt),
      'reasoningEffort': serializer.toJson<String>(reasoningEffort),
    };
  }

  AgentConfig copyWith({
    int? id,
    String? uuid,
    String? name,
    String? kind,
    String? command,
    String? args,
    String? endpoint,
    Value<String?> apiKeyEnc = const Value.absent(),
    String? model,
    String? systemPrompt,
    bool? isActive,
    int? createdAt,
    String? reasoningEffort,
  }) => AgentConfig(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    command: command ?? this.command,
    args: args ?? this.args,
    endpoint: endpoint ?? this.endpoint,
    apiKeyEnc: apiKeyEnc.present ? apiKeyEnc.value : this.apiKeyEnc,
    model: model ?? this.model,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    reasoningEffort: reasoningEffort ?? this.reasoningEffort,
  );
  AgentConfig copyWithCompanion(AgentConfigsCompanion data) {
    return AgentConfig(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      command: data.command.present ? data.command.value : this.command,
      args: data.args.present ? data.args.value : this.args,
      endpoint: data.endpoint.present ? data.endpoint.value : this.endpoint,
      apiKeyEnc: data.apiKeyEnc.present ? data.apiKeyEnc.value : this.apiKeyEnc,
      model: data.model.present ? data.model.value : this.model,
      systemPrompt: data.systemPrompt.present
          ? data.systemPrompt.value
          : this.systemPrompt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      reasoningEffort: data.reasoningEffort.present
          ? data.reasoningEffort.value
          : this.reasoningEffort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AgentConfig(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('command: $command, ')
          ..write('args: $args, ')
          ..write('endpoint: $endpoint, ')
          ..write('apiKeyEnc: $apiKeyEnc, ')
          ..write('model: $model, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('reasoningEffort: $reasoningEffort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uuid,
    name,
    kind,
    command,
    args,
    endpoint,
    apiKeyEnc,
    model,
    systemPrompt,
    isActive,
    createdAt,
    reasoningEffort,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AgentConfig &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.command == this.command &&
          other.args == this.args &&
          other.endpoint == this.endpoint &&
          other.apiKeyEnc == this.apiKeyEnc &&
          other.model == this.model &&
          other.systemPrompt == this.systemPrompt &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.reasoningEffort == this.reasoningEffort);
}

class AgentConfigsCompanion extends UpdateCompanion<AgentConfig> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> name;
  final Value<String> kind;
  final Value<String> command;
  final Value<String> args;
  final Value<String> endpoint;
  final Value<String?> apiKeyEnc;
  final Value<String> model;
  final Value<String> systemPrompt;
  final Value<bool> isActive;
  final Value<int> createdAt;
  final Value<String> reasoningEffort;
  const AgentConfigsCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.command = const Value.absent(),
    this.args = const Value.absent(),
    this.endpoint = const Value.absent(),
    this.apiKeyEnc = const Value.absent(),
    this.model = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.reasoningEffort = const Value.absent(),
  });
  AgentConfigsCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String name,
    required String kind,
    this.command = const Value.absent(),
    this.args = const Value.absent(),
    this.endpoint = const Value.absent(),
    this.apiKeyEnc = const Value.absent(),
    this.model = const Value.absent(),
    this.systemPrompt = const Value.absent(),
    this.isActive = const Value.absent(),
    required int createdAt,
    this.reasoningEffort = const Value.absent(),
  }) : uuid = Value(uuid),
       name = Value(name),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<AgentConfig> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<String>? command,
    Expression<String>? args,
    Expression<String>? endpoint,
    Expression<String>? apiKeyEnc,
    Expression<String>? model,
    Expression<String>? systemPrompt,
    Expression<bool>? isActive,
    Expression<int>? createdAt,
    Expression<String>? reasoningEffort,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (command != null) 'command': command,
      if (args != null) 'args': args,
      if (endpoint != null) 'endpoint': endpoint,
      if (apiKeyEnc != null) 'api_key_enc': apiKeyEnc,
      if (model != null) 'model': model,
      if (systemPrompt != null) 'system_prompt': systemPrompt,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
    });
  }

  AgentConfigsCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? name,
    Value<String>? kind,
    Value<String>? command,
    Value<String>? args,
    Value<String>? endpoint,
    Value<String?>? apiKeyEnc,
    Value<String>? model,
    Value<String>? systemPrompt,
    Value<bool>? isActive,
    Value<int>? createdAt,
    Value<String>? reasoningEffort,
  }) {
    return AgentConfigsCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      command: command ?? this.command,
      args: args ?? this.args,
      endpoint: endpoint ?? this.endpoint,
      apiKeyEnc: apiKeyEnc ?? this.apiKeyEnc,
      model: model ?? this.model,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (command.present) {
      map['command'] = Variable<String>(command.value);
    }
    if (args.present) {
      map['args'] = Variable<String>(args.value);
    }
    if (endpoint.present) {
      map['endpoint'] = Variable<String>(endpoint.value);
    }
    if (apiKeyEnc.present) {
      map['api_key_enc'] = Variable<String>(apiKeyEnc.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (systemPrompt.present) {
      map['system_prompt'] = Variable<String>(systemPrompt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (reasoningEffort.present) {
      map['reasoning_effort'] = Variable<String>(reasoningEffort.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AgentConfigsCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('command: $command, ')
          ..write('args: $args, ')
          ..write('endpoint: $endpoint, ')
          ..write('apiKeyEnc: $apiKeyEnc, ')
          ..write('model: $model, ')
          ..write('systemPrompt: $systemPrompt, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('reasoningEffort: $reasoningEffort')
          ..write(')'))
        .toString();
  }
}

class $ChatSessionsTable extends ChatSessions
    with TableInfo<$ChatSessionsTable, ChatSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _agentUuidMeta = const VerificationMeta(
    'agentUuid',
  );
  @override
  late final GeneratedColumn<String> agentUuid = GeneratedColumn<String>(
    'agent_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _hostNameMeta = const VerificationMeta(
    'hostName',
  );
  @override
  late final GeneratedColumn<String> hostName = GeneratedColumn<String>(
    'host_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _externalSessionIdMeta = const VerificationMeta(
    'externalSessionId',
  );
  @override
  late final GeneratedColumn<String> externalSessionId =
      GeneratedColumn<String>(
        'external_session_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    title,
    agentUuid,
    agentName,
    model,
    hostName,
    externalSessionId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('agent_uuid')) {
      context.handle(
        _agentUuidMeta,
        agentUuid.isAcceptableOrUnknown(data['agent_uuid']!, _agentUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_agentUuidMeta);
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    } else if (isInserting) {
      context.missing(_agentNameMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('host_name')) {
      context.handle(
        _hostNameMeta,
        hostName.isAcceptableOrUnknown(data['host_name']!, _hostNameMeta),
      );
    }
    if (data.containsKey('external_session_id')) {
      context.handle(
        _externalSessionIdMeta,
        externalSessionId.isAcceptableOrUnknown(
          data['external_session_id']!,
          _externalSessionIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      agentUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_uuid'],
      )!,
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      hostName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host_name'],
      )!,
      externalSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}external_session_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ChatSessionsTable createAlias(String alias) {
    return $ChatSessionsTable(attachedDatabase, alias);
  }
}

class ChatSession extends DataClass implements Insertable<ChatSession> {
  final int id;
  final String uuid;
  final String title;
  final String agentUuid;
  final String agentName;
  final String model;
  final String hostName;

  /// CLI 类 Agent 的会话 id（用于续接上下文）
  final String? externalSessionId;
  final int createdAt;
  final int updatedAt;
  const ChatSession({
    required this.id,
    required this.uuid,
    required this.title,
    required this.agentUuid,
    required this.agentName,
    required this.model,
    required this.hostName,
    this.externalSessionId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['title'] = Variable<String>(title);
    map['agent_uuid'] = Variable<String>(agentUuid);
    map['agent_name'] = Variable<String>(agentName);
    map['model'] = Variable<String>(model);
    map['host_name'] = Variable<String>(hostName);
    if (!nullToAbsent || externalSessionId != null) {
      map['external_session_id'] = Variable<String>(externalSessionId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  ChatSessionsCompanion toCompanion(bool nullToAbsent) {
    return ChatSessionsCompanion(
      id: Value(id),
      uuid: Value(uuid),
      title: Value(title),
      agentUuid: Value(agentUuid),
      agentName: Value(agentName),
      model: Value(model),
      hostName: Value(hostName),
      externalSessionId: externalSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(externalSessionId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ChatSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatSession(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      title: serializer.fromJson<String>(json['title']),
      agentUuid: serializer.fromJson<String>(json['agentUuid']),
      agentName: serializer.fromJson<String>(json['agentName']),
      model: serializer.fromJson<String>(json['model']),
      hostName: serializer.fromJson<String>(json['hostName']),
      externalSessionId: serializer.fromJson<String?>(
        json['externalSessionId'],
      ),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'title': serializer.toJson<String>(title),
      'agentUuid': serializer.toJson<String>(agentUuid),
      'agentName': serializer.toJson<String>(agentName),
      'model': serializer.toJson<String>(model),
      'hostName': serializer.toJson<String>(hostName),
      'externalSessionId': serializer.toJson<String?>(externalSessionId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  ChatSession copyWith({
    int? id,
    String? uuid,
    String? title,
    String? agentUuid,
    String? agentName,
    String? model,
    String? hostName,
    Value<String?> externalSessionId = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => ChatSession(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    title: title ?? this.title,
    agentUuid: agentUuid ?? this.agentUuid,
    agentName: agentName ?? this.agentName,
    model: model ?? this.model,
    hostName: hostName ?? this.hostName,
    externalSessionId: externalSessionId.present
        ? externalSessionId.value
        : this.externalSessionId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ChatSession copyWithCompanion(ChatSessionsCompanion data) {
    return ChatSession(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      title: data.title.present ? data.title.value : this.title,
      agentUuid: data.agentUuid.present ? data.agentUuid.value : this.agentUuid,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      model: data.model.present ? data.model.value : this.model,
      hostName: data.hostName.present ? data.hostName.value : this.hostName,
      externalSessionId: data.externalSessionId.present
          ? data.externalSessionId.value
          : this.externalSessionId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatSession(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('title: $title, ')
          ..write('agentUuid: $agentUuid, ')
          ..write('agentName: $agentName, ')
          ..write('model: $model, ')
          ..write('hostName: $hostName, ')
          ..write('externalSessionId: $externalSessionId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uuid,
    title,
    agentUuid,
    agentName,
    model,
    hostName,
    externalSessionId,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatSession &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.title == this.title &&
          other.agentUuid == this.agentUuid &&
          other.agentName == this.agentName &&
          other.model == this.model &&
          other.hostName == this.hostName &&
          other.externalSessionId == this.externalSessionId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ChatSessionsCompanion extends UpdateCompanion<ChatSession> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> title;
  final Value<String> agentUuid;
  final Value<String> agentName;
  final Value<String> model;
  final Value<String> hostName;
  final Value<String?> externalSessionId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  const ChatSessionsCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.title = const Value.absent(),
    this.agentUuid = const Value.absent(),
    this.agentName = const Value.absent(),
    this.model = const Value.absent(),
    this.hostName = const Value.absent(),
    this.externalSessionId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ChatSessionsCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String title,
    required String agentUuid,
    required String agentName,
    this.model = const Value.absent(),
    this.hostName = const Value.absent(),
    this.externalSessionId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
  }) : uuid = Value(uuid),
       title = Value(title),
       agentUuid = Value(agentUuid),
       agentName = Value(agentName),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ChatSession> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? title,
    Expression<String>? agentUuid,
    Expression<String>? agentName,
    Expression<String>? model,
    Expression<String>? hostName,
    Expression<String>? externalSessionId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (title != null) 'title': title,
      if (agentUuid != null) 'agent_uuid': agentUuid,
      if (agentName != null) 'agent_name': agentName,
      if (model != null) 'model': model,
      if (hostName != null) 'host_name': hostName,
      if (externalSessionId != null) 'external_session_id': externalSessionId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ChatSessionsCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? title,
    Value<String>? agentUuid,
    Value<String>? agentName,
    Value<String>? model,
    Value<String>? hostName,
    Value<String?>? externalSessionId,
    Value<int>? createdAt,
    Value<int>? updatedAt,
  }) {
    return ChatSessionsCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      title: title ?? this.title,
      agentUuid: agentUuid ?? this.agentUuid,
      agentName: agentName ?? this.agentName,
      model: model ?? this.model,
      hostName: hostName ?? this.hostName,
      externalSessionId: externalSessionId ?? this.externalSessionId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (agentUuid.present) {
      map['agent_uuid'] = Variable<String>(agentUuid.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (hostName.present) {
      map['host_name'] = Variable<String>(hostName.value);
    }
    if (externalSessionId.present) {
      map['external_session_id'] = Variable<String>(externalSessionId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatSessionsCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('title: $title, ')
          ..write('agentUuid: $agentUuid, ')
          ..write('agentName: $agentName, ')
          ..write('model: $model, ')
          ..write('hostName: $hostName, ')
          ..write('externalSessionId: $externalSessionId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputTokensMeta = const VerificationMeta(
    'inputTokens',
  );
  @override
  late final GeneratedColumn<int> inputTokens = GeneratedColumn<int>(
    'input_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _outputTokensMeta = const VerificationMeta(
    'outputTokens',
  );
  @override
  late final GeneratedColumn<int> outputTokens = GeneratedColumn<int>(
    'output_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    role,
    content,
    inputTokens,
    outputTokens,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('input_tokens')) {
      context.handle(
        _inputTokensMeta,
        inputTokens.isAcceptableOrUnknown(
          data['input_tokens']!,
          _inputTokensMeta,
        ),
      );
    }
    if (data.containsKey('output_tokens')) {
      context.handle(
        _outputTokensMeta,
        outputTokens.isAcceptableOrUnknown(
          data['output_tokens']!,
          _outputTokensMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}session_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      inputTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}input_tokens'],
      )!,
      outputTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}output_tokens'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessage extends DataClass implements Insertable<ChatMessage> {
  final int id;
  final int sessionId;

  /// 角色：user / assistant / error
  final String role;
  final String content;
  final int inputTokens;
  final int outputTokens;
  final int createdAt;
  const ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.inputTokens,
    required this.outputTokens,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<int>(sessionId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    map['input_tokens'] = Variable<int>(inputTokens);
    map['output_tokens'] = Variable<int>(outputTokens);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      role: Value(role),
      content: Value(content),
      inputTokens: Value(inputTokens),
      outputTokens: Value(outputTokens),
      createdAt: Value(createdAt),
    );
  }

  factory ChatMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessage(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<int>(json['sessionId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      inputTokens: serializer.fromJson<int>(json['inputTokens']),
      outputTokens: serializer.fromJson<int>(json['outputTokens']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<int>(sessionId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'inputTokens': serializer.toJson<int>(inputTokens),
      'outputTokens': serializer.toJson<int>(outputTokens),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ChatMessage copyWith({
    int? id,
    int? sessionId,
    String? role,
    String? content,
    int? inputTokens,
    int? outputTokens,
    int? createdAt,
  }) => ChatMessage(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    role: role ?? this.role,
    content: content ?? this.content,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    createdAt: createdAt ?? this.createdAt,
  );
  ChatMessage copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessage(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      inputTokens: data.inputTokens.present
          ? data.inputTokens.value
          : this.inputTokens,
      outputTokens: data.outputTokens.present
          ? data.outputTokens.value
          : this.outputTokens,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessage(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    role,
    content,
    inputTokens,
    outputTokens,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessage &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.role == this.role &&
          other.content == this.content &&
          other.inputTokens == this.inputTokens &&
          other.outputTokens == this.outputTokens &&
          other.createdAt == this.createdAt);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessage> {
  final Value<int> id;
  final Value<int> sessionId;
  final Value<String> role;
  final Value<String> content;
  final Value<int> inputTokens;
  final Value<int> outputTokens;
  final Value<int> createdAt;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    this.id = const Value.absent(),
    required int sessionId,
    required String role,
    required String content,
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    required int createdAt,
  }) : sessionId = Value(sessionId),
       role = Value(role),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<ChatMessage> custom({
    Expression<int>? id,
    Expression<int>? sessionId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<int>? inputTokens,
    Expression<int>? outputTokens,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (inputTokens != null) 'input_tokens': inputTokens,
      if (outputTokens != null) 'output_tokens': outputTokens,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<int>? id,
    Value<int>? sessionId,
    Value<String>? role,
    Value<String>? content,
    Value<int>? inputTokens,
    Value<int>? outputTokens,
    Value<int>? createdAt,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (inputTokens.present) {
      map['input_tokens'] = Variable<int>(inputTokens.value);
    }
    if (outputTokens.present) {
      map['output_tokens'] = Variable<int>(outputTokens.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $TokenUsagesTable extends TokenUsages
    with TableInfo<$TokenUsagesTable, TokenUsage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TokenUsagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _agentUuidMeta = const VerificationMeta(
    'agentUuid',
  );
  @override
  late final GeneratedColumn<String> agentUuid = GeneratedColumn<String>(
    'agent_uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _agentNameMeta = const VerificationMeta(
    'agentName',
  );
  @override
  late final GeneratedColumn<String> agentName = GeneratedColumn<String>(
    'agent_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputTokensMeta = const VerificationMeta(
    'inputTokens',
  );
  @override
  late final GeneratedColumn<int> inputTokens = GeneratedColumn<int>(
    'input_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _outputTokensMeta = const VerificationMeta(
    'outputTokens',
  );
  @override
  late final GeneratedColumn<int> outputTokens = GeneratedColumn<int>(
    'output_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    day,
    agentUuid,
    agentName,
    model,
    inputTokens,
    outputTokens,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'token_usages';
  @override
  VerificationContext validateIntegrity(
    Insertable<TokenUsage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('agent_uuid')) {
      context.handle(
        _agentUuidMeta,
        agentUuid.isAcceptableOrUnknown(data['agent_uuid']!, _agentUuidMeta),
      );
    } else if (isInserting) {
      context.missing(_agentUuidMeta);
    }
    if (data.containsKey('agent_name')) {
      context.handle(
        _agentNameMeta,
        agentName.isAcceptableOrUnknown(data['agent_name']!, _agentNameMeta),
      );
    } else if (isInserting) {
      context.missing(_agentNameMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('input_tokens')) {
      context.handle(
        _inputTokensMeta,
        inputTokens.isAcceptableOrUnknown(
          data['input_tokens']!,
          _inputTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inputTokensMeta);
    }
    if (data.containsKey('output_tokens')) {
      context.handle(
        _outputTokensMeta,
        outputTokens.isAcceptableOrUnknown(
          data['output_tokens']!,
          _outputTokensMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_outputTokensMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TokenUsage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TokenUsage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      agentUuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_uuid'],
      )!,
      agentName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_name'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      inputTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}input_tokens'],
      )!,
      outputTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}output_tokens'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TokenUsagesTable createAlias(String alias) {
    return $TokenUsagesTable(attachedDatabase, alias);
  }
}

class TokenUsage extends DataClass implements Insertable<TokenUsage> {
  final int id;

  /// 日期键 yyyy-MM-dd（本地时间）
  final String day;
  final String agentUuid;
  final String agentName;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int createdAt;
  const TokenUsage({
    required this.id,
    required this.day,
    required this.agentUuid,
    required this.agentName,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['day'] = Variable<String>(day);
    map['agent_uuid'] = Variable<String>(agentUuid);
    map['agent_name'] = Variable<String>(agentName);
    map['model'] = Variable<String>(model);
    map['input_tokens'] = Variable<int>(inputTokens);
    map['output_tokens'] = Variable<int>(outputTokens);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  TokenUsagesCompanion toCompanion(bool nullToAbsent) {
    return TokenUsagesCompanion(
      id: Value(id),
      day: Value(day),
      agentUuid: Value(agentUuid),
      agentName: Value(agentName),
      model: Value(model),
      inputTokens: Value(inputTokens),
      outputTokens: Value(outputTokens),
      createdAt: Value(createdAt),
    );
  }

  factory TokenUsage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TokenUsage(
      id: serializer.fromJson<int>(json['id']),
      day: serializer.fromJson<String>(json['day']),
      agentUuid: serializer.fromJson<String>(json['agentUuid']),
      agentName: serializer.fromJson<String>(json['agentName']),
      model: serializer.fromJson<String>(json['model']),
      inputTokens: serializer.fromJson<int>(json['inputTokens']),
      outputTokens: serializer.fromJson<int>(json['outputTokens']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'day': serializer.toJson<String>(day),
      'agentUuid': serializer.toJson<String>(agentUuid),
      'agentName': serializer.toJson<String>(agentName),
      'model': serializer.toJson<String>(model),
      'inputTokens': serializer.toJson<int>(inputTokens),
      'outputTokens': serializer.toJson<int>(outputTokens),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  TokenUsage copyWith({
    int? id,
    String? day,
    String? agentUuid,
    String? agentName,
    String? model,
    int? inputTokens,
    int? outputTokens,
    int? createdAt,
  }) => TokenUsage(
    id: id ?? this.id,
    day: day ?? this.day,
    agentUuid: agentUuid ?? this.agentUuid,
    agentName: agentName ?? this.agentName,
    model: model ?? this.model,
    inputTokens: inputTokens ?? this.inputTokens,
    outputTokens: outputTokens ?? this.outputTokens,
    createdAt: createdAt ?? this.createdAt,
  );
  TokenUsage copyWithCompanion(TokenUsagesCompanion data) {
    return TokenUsage(
      id: data.id.present ? data.id.value : this.id,
      day: data.day.present ? data.day.value : this.day,
      agentUuid: data.agentUuid.present ? data.agentUuid.value : this.agentUuid,
      agentName: data.agentName.present ? data.agentName.value : this.agentName,
      model: data.model.present ? data.model.value : this.model,
      inputTokens: data.inputTokens.present
          ? data.inputTokens.value
          : this.inputTokens,
      outputTokens: data.outputTokens.present
          ? data.outputTokens.value
          : this.outputTokens,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TokenUsage(')
          ..write('id: $id, ')
          ..write('day: $day, ')
          ..write('agentUuid: $agentUuid, ')
          ..write('agentName: $agentName, ')
          ..write('model: $model, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    day,
    agentUuid,
    agentName,
    model,
    inputTokens,
    outputTokens,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TokenUsage &&
          other.id == this.id &&
          other.day == this.day &&
          other.agentUuid == this.agentUuid &&
          other.agentName == this.agentName &&
          other.model == this.model &&
          other.inputTokens == this.inputTokens &&
          other.outputTokens == this.outputTokens &&
          other.createdAt == this.createdAt);
}

class TokenUsagesCompanion extends UpdateCompanion<TokenUsage> {
  final Value<int> id;
  final Value<String> day;
  final Value<String> agentUuid;
  final Value<String> agentName;
  final Value<String> model;
  final Value<int> inputTokens;
  final Value<int> outputTokens;
  final Value<int> createdAt;
  const TokenUsagesCompanion({
    this.id = const Value.absent(),
    this.day = const Value.absent(),
    this.agentUuid = const Value.absent(),
    this.agentName = const Value.absent(),
    this.model = const Value.absent(),
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  TokenUsagesCompanion.insert({
    this.id = const Value.absent(),
    required String day,
    required String agentUuid,
    required String agentName,
    required String model,
    required int inputTokens,
    required int outputTokens,
    required int createdAt,
  }) : day = Value(day),
       agentUuid = Value(agentUuid),
       agentName = Value(agentName),
       model = Value(model),
       inputTokens = Value(inputTokens),
       outputTokens = Value(outputTokens),
       createdAt = Value(createdAt);
  static Insertable<TokenUsage> custom({
    Expression<int>? id,
    Expression<String>? day,
    Expression<String>? agentUuid,
    Expression<String>? agentName,
    Expression<String>? model,
    Expression<int>? inputTokens,
    Expression<int>? outputTokens,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (day != null) 'day': day,
      if (agentUuid != null) 'agent_uuid': agentUuid,
      if (agentName != null) 'agent_name': agentName,
      if (model != null) 'model': model,
      if (inputTokens != null) 'input_tokens': inputTokens,
      if (outputTokens != null) 'output_tokens': outputTokens,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  TokenUsagesCompanion copyWith({
    Value<int>? id,
    Value<String>? day,
    Value<String>? agentUuid,
    Value<String>? agentName,
    Value<String>? model,
    Value<int>? inputTokens,
    Value<int>? outputTokens,
    Value<int>? createdAt,
  }) {
    return TokenUsagesCompanion(
      id: id ?? this.id,
      day: day ?? this.day,
      agentUuid: agentUuid ?? this.agentUuid,
      agentName: agentName ?? this.agentName,
      model: model ?? this.model,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (agentUuid.present) {
      map['agent_uuid'] = Variable<String>(agentUuid.value);
    }
    if (agentName.present) {
      map['agent_name'] = Variable<String>(agentName.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (inputTokens.present) {
      map['input_tokens'] = Variable<int>(inputTokens.value);
    }
    if (outputTokens.present) {
      map['output_tokens'] = Variable<int>(outputTokens.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TokenUsagesCompanion(')
          ..write('id: $id, ')
          ..write('day: $day, ')
          ..write('agentUuid: $agentUuid, ')
          ..write('agentName: $agentName, ')
          ..write('model: $model, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $HostGroupsTable hostGroups = $HostGroupsTable(this);
  late final $HostsTable hosts = $HostsTable(this);
  late final $SshKeysTable sshKeys = $SshKeysTable(this);
  late final $SnippetsTable snippets = $SnippetsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $AgentConfigsTable agentConfigs = $AgentConfigsTable(this);
  late final $ChatSessionsTable chatSessions = $ChatSessionsTable(this);
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $TokenUsagesTable tokenUsages = $TokenUsagesTable(this);
  late final Index idxGroupsUuid = Index(
    'idx_groups_uuid',
    'CREATE UNIQUE INDEX idx_groups_uuid ON host_groups (uuid)',
  );
  late final Index idxGroupsSort = Index(
    'idx_groups_sort',
    'CREATE INDEX idx_groups_sort ON host_groups (sort_order)',
  );
  late final Index idxHostsUuid = Index(
    'idx_hosts_uuid',
    'CREATE UNIQUE INDEX idx_hosts_uuid ON hosts (uuid)',
  );
  late final Index idxHostsProtocolGroup = Index(
    'idx_hosts_protocol_group',
    'CREATE INDEX idx_hosts_protocol_group ON hosts (protocol, group_uuid)',
  );
  late final Index idxHostsSync = Index(
    'idx_hosts_sync',
    'CREATE INDEX idx_hosts_sync ON hosts (sync_enabled)',
  );
  late final Index idxHostsLastConnected = Index(
    'idx_hosts_last_connected',
    'CREATE INDEX idx_hosts_last_connected ON hosts (last_connected_at)',
  );
  late final Index idxKeysUuid = Index(
    'idx_keys_uuid',
    'CREATE UNIQUE INDEX idx_keys_uuid ON ssh_keys (uuid)',
  );
  late final Index idxKeysCreated = Index(
    'idx_keys_created',
    'CREATE INDEX idx_keys_created ON ssh_keys (created_at)',
  );
  late final Index idxSnippetsUuid = Index(
    'idx_snippets_uuid',
    'CREATE UNIQUE INDEX idx_snippets_uuid ON snippets (uuid)',
  );
  late final Index idxSnippetsSort = Index(
    'idx_snippets_sort',
    'CREATE INDEX idx_snippets_sort ON snippets (sort_order)',
  );
  late final Index idxAgentsUuid = Index(
    'idx_agents_uuid',
    'CREATE UNIQUE INDEX idx_agents_uuid ON agent_configs (uuid)',
  );
  late final Index idxAgentsActive = Index(
    'idx_agents_active',
    'CREATE INDEX idx_agents_active ON agent_configs (is_active)',
  );
  late final Index idxAgentsCreated = Index(
    'idx_agents_created',
    'CREATE INDEX idx_agents_created ON agent_configs (created_at)',
  );
  late final Index idxChatSessionsUuid = Index(
    'idx_chat_sessions_uuid',
    'CREATE UNIQUE INDEX idx_chat_sessions_uuid ON chat_sessions (uuid)',
  );
  late final Index idxChatSessionsUpdated = Index(
    'idx_chat_sessions_updated',
    'CREATE INDEX idx_chat_sessions_updated ON chat_sessions (updated_at)',
  );
  late final Index idxChatSessionsAgent = Index(
    'idx_chat_sessions_agent',
    'CREATE INDEX idx_chat_sessions_agent ON chat_sessions (agent_uuid)',
  );
  late final Index idxChatMessagesSession = Index(
    'idx_chat_messages_session',
    'CREATE INDEX idx_chat_messages_session ON chat_messages (session_id, created_at)',
  );
  late final Index idxTokenDay = Index(
    'idx_token_day',
    'CREATE INDEX idx_token_day ON token_usages (day)',
  );
  late final Index idxTokenDayAgent = Index(
    'idx_token_day_agent',
    'CREATE INDEX idx_token_day_agent ON token_usages (day, agent_uuid)',
  );
  late final Index idxTokenDayModel = Index(
    'idx_token_day_model',
    'CREATE INDEX idx_token_day_model ON token_usages (day, model)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    hostGroups,
    hosts,
    sshKeys,
    snippets,
    appSettings,
    agentConfigs,
    chatSessions,
    chatMessages,
    tokenUsages,
    idxGroupsUuid,
    idxGroupsSort,
    idxHostsUuid,
    idxHostsProtocolGroup,
    idxHostsSync,
    idxHostsLastConnected,
    idxKeysUuid,
    idxKeysCreated,
    idxSnippetsUuid,
    idxSnippetsSort,
    idxAgentsUuid,
    idxAgentsActive,
    idxAgentsCreated,
    idxChatSessionsUuid,
    idxChatSessionsUpdated,
    idxChatSessionsAgent,
    idxChatMessagesSession,
    idxTokenDay,
    idxTokenDayAgent,
    idxTokenDayModel,
  ];
}

typedef $$HostGroupsTableCreateCompanionBuilder = HostGroupsCompanion Function({
  Value<int> id,
  required String uuid,
  required String name,
  Value<int> sortOrder,
  required int updatedAt,
});
typedef $$HostGroupsTableUpdateCompanionBuilder = HostGroupsCompanion Function({
  Value<int> id,
  Value<String> uuid,
  Value<String> name,
  Value<int> sortOrder,
  Value<int> updatedAt,
});

class $$HostGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $HostGroupsTable> {
  $$HostGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HostGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $HostGroupsTable> {
  $$HostGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HostGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HostGroupsTable> {
  $$HostGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$HostGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HostGroupsTable,
          HostGroup,
          $$HostGroupsTableFilterComposer,
          $$HostGroupsTableOrderingComposer,
          $$HostGroupsTableAnnotationComposer,
          $$HostGroupsTableCreateCompanionBuilder,
          $$HostGroupsTableUpdateCompanionBuilder,
          (
            HostGroup,
            BaseReferences<_$AppDatabase, $HostGroupsTable, HostGroup>,
          ),
          HostGroup,
          PrefetchHooks Function()
        > {
  $$HostGroupsTableTableManager(_$AppDatabase db, $HostGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => HostGroupsCompanion(
                id: id,
                uuid: uuid,
                name: name,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                required int updatedAt,
              }) => HostGroupsCompanion.insert(
                id: id,
                uuid: uuid,
                name: name,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HostGroupsTable, HostGroup>(table),
                  BaseReferences<_$AppDatabase, $HostGroupsTable, HostGroup>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HostGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HostGroupsTable,
      HostGroup,
      $$HostGroupsTableFilterComposer,
      $$HostGroupsTableOrderingComposer,
      $$HostGroupsTableAnnotationComposer,
      $$HostGroupsTableCreateCompanionBuilder,
      $$HostGroupsTableUpdateCompanionBuilder,
      (HostGroup, BaseReferences<_$AppDatabase, $HostGroupsTable, HostGroup>),
      HostGroup,
      PrefetchHooks Function()
    >;
typedef $$HostsTableCreateCompanionBuilder = HostsCompanion Function({
  Value<int> id,
  required String uuid,
  required String protocol,
  required String name,
  Value<String?> groupUuid,
  required String address,
  required int port,
  Value<String> username,
  Value<String> authType,
  Value<String?> passwordEnc,
  Value<bool> savePassword,
  Value<String?> keyUuid,
  Value<String> jumpChain,
  Value<String> proxyType,
  Value<String> proxyHost,
  Value<int> proxyPort,
  Value<String> proxyUser,
  Value<String?> proxyPassEnc,
  Value<String?> osId,
  Value<String?> osName,
  Value<String?> hostKeyFingerprint,
  Value<String> extraJson,
  Value<String> note,
  Value<bool> syncEnabled,
  Value<int?> syncedAt,
  required int updatedAt,
  required int createdAt,
  Value<int?> lastConnectedAt,
});
typedef $$HostsTableUpdateCompanionBuilder = HostsCompanion Function({
  Value<int> id,
  Value<String> uuid,
  Value<String> protocol,
  Value<String> name,
  Value<String?> groupUuid,
  Value<String> address,
  Value<int> port,
  Value<String> username,
  Value<String> authType,
  Value<String?> passwordEnc,
  Value<bool> savePassword,
  Value<String?> keyUuid,
  Value<String> jumpChain,
  Value<String> proxyType,
  Value<String> proxyHost,
  Value<int> proxyPort,
  Value<String> proxyUser,
  Value<String?> proxyPassEnc,
  Value<String?> osId,
  Value<String?> osName,
  Value<String?> hostKeyFingerprint,
  Value<String> extraJson,
  Value<String> note,
  Value<bool> syncEnabled,
  Value<int?> syncedAt,
  Value<int> updatedAt,
  Value<int> createdAt,
  Value<int?> lastConnectedAt,
});

class $$HostsTableFilterComposer extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupUuid => $composableBuilder(
    column: $table.groupUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passwordEnc => $composableBuilder(
    column: $table.passwordEnc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get savePassword => $composableBuilder(
    column: $table.savePassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyUuid => $composableBuilder(
    column: $table.keyUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jumpChain => $composableBuilder(
    column: $table.jumpChain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proxyType => $composableBuilder(
    column: $table.proxyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proxyHost => $composableBuilder(
    column: $table.proxyHost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get proxyPort => $composableBuilder(
    column: $table.proxyPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proxyUser => $composableBuilder(
    column: $table.proxyUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proxyPassEnc => $composableBuilder(
    column: $table.proxyPassEnc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get osId => $composableBuilder(
    column: $table.osId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get osName => $composableBuilder(
    column: $table.osName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostKeyFingerprint => $composableBuilder(
    column: $table.hostKeyFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extraJson => $composableBuilder(
    column: $table.extraJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get syncEnabled => $composableBuilder(
    column: $table.syncEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HostsTableOrderingComposer
    extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupUuid => $composableBuilder(
    column: $table.groupUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authType => $composableBuilder(
    column: $table.authType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordEnc => $composableBuilder(
    column: $table.passwordEnc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get savePassword => $composableBuilder(
    column: $table.savePassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyUuid => $composableBuilder(
    column: $table.keyUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jumpChain => $composableBuilder(
    column: $table.jumpChain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proxyType => $composableBuilder(
    column: $table.proxyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proxyHost => $composableBuilder(
    column: $table.proxyHost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get proxyPort => $composableBuilder(
    column: $table.proxyPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proxyUser => $composableBuilder(
    column: $table.proxyUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proxyPassEnc => $composableBuilder(
    column: $table.proxyPassEnc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get osId => $composableBuilder(
    column: $table.osId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get osName => $composableBuilder(
    column: $table.osName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostKeyFingerprint => $composableBuilder(
    column: $table.hostKeyFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extraJson => $composableBuilder(
    column: $table.extraJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get syncEnabled => $composableBuilder(
    column: $table.syncEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HostsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HostsTable> {
  $$HostsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get groupUuid =>
      $composableBuilder(column: $table.groupUuid, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get authType =>
      $composableBuilder(column: $table.authType, builder: (column) => column);

  GeneratedColumn<String> get passwordEnc => $composableBuilder(
    column: $table.passwordEnc,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get savePassword => $composableBuilder(
    column: $table.savePassword,
    builder: (column) => column,
  );

  GeneratedColumn<String> get keyUuid =>
      $composableBuilder(column: $table.keyUuid, builder: (column) => column);

  GeneratedColumn<String> get jumpChain =>
      $composableBuilder(column: $table.jumpChain, builder: (column) => column);

  GeneratedColumn<String> get proxyType =>
      $composableBuilder(column: $table.proxyType, builder: (column) => column);

  GeneratedColumn<String> get proxyHost =>
      $composableBuilder(column: $table.proxyHost, builder: (column) => column);

  GeneratedColumn<int> get proxyPort =>
      $composableBuilder(column: $table.proxyPort, builder: (column) => column);

  GeneratedColumn<String> get proxyUser =>
      $composableBuilder(column: $table.proxyUser, builder: (column) => column);

  GeneratedColumn<String> get proxyPassEnc => $composableBuilder(
    column: $table.proxyPassEnc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get osId =>
      $composableBuilder(column: $table.osId, builder: (column) => column);

  GeneratedColumn<String> get osName =>
      $composableBuilder(column: $table.osName, builder: (column) => column);

  GeneratedColumn<String> get hostKeyFingerprint => $composableBuilder(
    column: $table.hostKeyFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get extraJson =>
      $composableBuilder(column: $table.extraJson, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<bool> get syncEnabled => $composableBuilder(
    column: $table.syncEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<int> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => column,
  );
}

class $$HostsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HostsTable,
          Host,
          $$HostsTableFilterComposer,
          $$HostsTableOrderingComposer,
          $$HostsTableAnnotationComposer,
          $$HostsTableCreateCompanionBuilder,
          $$HostsTableUpdateCompanionBuilder,
          (Host, BaseReferences<_$AppDatabase, $HostsTable, Host>),
          Host,
          PrefetchHooks Function()
        > {
  $$HostsTableTableManager(_$AppDatabase db, $HostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> protocol = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> groupUuid = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> authType = const Value.absent(),
                Value<String?> passwordEnc = const Value.absent(),
                Value<bool> savePassword = const Value.absent(),
                Value<String?> keyUuid = const Value.absent(),
                Value<String> jumpChain = const Value.absent(),
                Value<String> proxyType = const Value.absent(),
                Value<String> proxyHost = const Value.absent(),
                Value<int> proxyPort = const Value.absent(),
                Value<String> proxyUser = const Value.absent(),
                Value<String?> proxyPassEnc = const Value.absent(),
                Value<String?> osId = const Value.absent(),
                Value<String?> osName = const Value.absent(),
                Value<String?> hostKeyFingerprint = const Value.absent(),
                Value<String> extraJson = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<bool> syncEnabled = const Value.absent(),
                Value<int?> syncedAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> lastConnectedAt = const Value.absent(),
              }) => HostsCompanion(
                id: id,
                uuid: uuid,
                protocol: protocol,
                name: name,
                groupUuid: groupUuid,
                address: address,
                port: port,
                username: username,
                authType: authType,
                passwordEnc: passwordEnc,
                savePassword: savePassword,
                keyUuid: keyUuid,
                jumpChain: jumpChain,
                proxyType: proxyType,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                proxyUser: proxyUser,
                proxyPassEnc: proxyPassEnc,
                osId: osId,
                osName: osName,
                hostKeyFingerprint: hostKeyFingerprint,
                extraJson: extraJson,
                note: note,
                syncEnabled: syncEnabled,
                syncedAt: syncedAt,
                updatedAt: updatedAt,
                createdAt: createdAt,
                lastConnectedAt: lastConnectedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String protocol,
                required String name,
                Value<String?> groupUuid = const Value.absent(),
                required String address,
                required int port,
                Value<String> username = const Value.absent(),
                Value<String> authType = const Value.absent(),
                Value<String?> passwordEnc = const Value.absent(),
                Value<bool> savePassword = const Value.absent(),
                Value<String?> keyUuid = const Value.absent(),
                Value<String> jumpChain = const Value.absent(),
                Value<String> proxyType = const Value.absent(),
                Value<String> proxyHost = const Value.absent(),
                Value<int> proxyPort = const Value.absent(),
                Value<String> proxyUser = const Value.absent(),
                Value<String?> proxyPassEnc = const Value.absent(),
                Value<String?> osId = const Value.absent(),
                Value<String?> osName = const Value.absent(),
                Value<String?> hostKeyFingerprint = const Value.absent(),
                Value<String> extraJson = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<bool> syncEnabled = const Value.absent(),
                Value<int?> syncedAt = const Value.absent(),
                required int updatedAt,
                required int createdAt,
                Value<int?> lastConnectedAt = const Value.absent(),
              }) => HostsCompanion.insert(
                id: id,
                uuid: uuid,
                protocol: protocol,
                name: name,
                groupUuid: groupUuid,
                address: address,
                port: port,
                username: username,
                authType: authType,
                passwordEnc: passwordEnc,
                savePassword: savePassword,
                keyUuid: keyUuid,
                jumpChain: jumpChain,
                proxyType: proxyType,
                proxyHost: proxyHost,
                proxyPort: proxyPort,
                proxyUser: proxyUser,
                proxyPassEnc: proxyPassEnc,
                osId: osId,
                osName: osName,
                hostKeyFingerprint: hostKeyFingerprint,
                extraJson: extraJson,
                note: note,
                syncEnabled: syncEnabled,
                syncedAt: syncedAt,
                updatedAt: updatedAt,
                createdAt: createdAt,
                lastConnectedAt: lastConnectedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HostsTable, Host>(table),
                  BaseReferences<_$AppDatabase, $HostsTable, Host>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HostsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HostsTable,
      Host,
      $$HostsTableFilterComposer,
      $$HostsTableOrderingComposer,
      $$HostsTableAnnotationComposer,
      $$HostsTableCreateCompanionBuilder,
      $$HostsTableUpdateCompanionBuilder,
      (Host, BaseReferences<_$AppDatabase, $HostsTable, Host>),
      Host,
      PrefetchHooks Function()
    >;
typedef $$SshKeysTableCreateCompanionBuilder = SshKeysCompanion Function({
  Value<int> id,
  required String uuid,
  required String name,
  required String keyType,
  required String privateKeyEnc,
  Value<String?> passphraseEnc,
  Value<String> publicKey,
  required int createdAt,
  required int updatedAt,
});
typedef $$SshKeysTableUpdateCompanionBuilder = SshKeysCompanion Function({
  Value<int> id,
  Value<String> uuid,
  Value<String> name,
  Value<String> keyType,
  Value<String> privateKeyEnc,
  Value<String?> passphraseEnc,
  Value<String> publicKey,
  Value<int> createdAt,
  Value<int> updatedAt,
});

class $$SshKeysTableFilterComposer
    extends Composer<_$AppDatabase, $SshKeysTable> {
  $$SshKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyType => $composableBuilder(
    column: $table.keyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get privateKeyEnc => $composableBuilder(
    column: $table.privateKeyEnc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passphraseEnc => $composableBuilder(
    column: $table.passphraseEnc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SshKeysTableOrderingComposer
    extends Composer<_$AppDatabase, $SshKeysTable> {
  $$SshKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyType => $composableBuilder(
    column: $table.keyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get privateKeyEnc => $composableBuilder(
    column: $table.privateKeyEnc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passphraseEnc => $composableBuilder(
    column: $table.passphraseEnc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SshKeysTableAnnotationComposer
    extends Composer<_$AppDatabase, $SshKeysTable> {
  $$SshKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get keyType =>
      $composableBuilder(column: $table.keyType, builder: (column) => column);

  GeneratedColumn<String> get privateKeyEnc => $composableBuilder(
    column: $table.privateKeyEnc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get passphraseEnc => $composableBuilder(
    column: $table.passphraseEnc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SshKeysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SshKeysTable,
          SshKey,
          $$SshKeysTableFilterComposer,
          $$SshKeysTableOrderingComposer,
          $$SshKeysTableAnnotationComposer,
          $$SshKeysTableCreateCompanionBuilder,
          $$SshKeysTableUpdateCompanionBuilder,
          (SshKey, BaseReferences<_$AppDatabase, $SshKeysTable, SshKey>),
          SshKey,
          PrefetchHooks Function()
        > {
  $$SshKeysTableTableManager(_$AppDatabase db, $SshKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SshKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SshKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SshKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> keyType = const Value.absent(),
                Value<String> privateKeyEnc = const Value.absent(),
                Value<String?> passphraseEnc = const Value.absent(),
                Value<String> publicKey = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => SshKeysCompanion(
                id: id,
                uuid: uuid,
                name: name,
                keyType: keyType,
                privateKeyEnc: privateKeyEnc,
                passphraseEnc: passphraseEnc,
                publicKey: publicKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String name,
                required String keyType,
                required String privateKeyEnc,
                Value<String?> passphraseEnc = const Value.absent(),
                Value<String> publicKey = const Value.absent(),
                required int createdAt,
                required int updatedAt,
              }) => SshKeysCompanion.insert(
                id: id,
                uuid: uuid,
                name: name,
                keyType: keyType,
                privateKeyEnc: privateKeyEnc,
                passphraseEnc: passphraseEnc,
                publicKey: publicKey,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SshKeysTable, SshKey>(table),
                  BaseReferences<_$AppDatabase, $SshKeysTable, SshKey>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SshKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SshKeysTable,
      SshKey,
      $$SshKeysTableFilterComposer,
      $$SshKeysTableOrderingComposer,
      $$SshKeysTableAnnotationComposer,
      $$SshKeysTableCreateCompanionBuilder,
      $$SshKeysTableUpdateCompanionBuilder,
      (SshKey, BaseReferences<_$AppDatabase, $SshKeysTable, SshKey>),
      SshKey,
      PrefetchHooks Function()
    >;
typedef $$SnippetsTableCreateCompanionBuilder = SnippetsCompanion Function({
  Value<int> id,
  required String uuid,
  required String name,
  Value<String> content,
  Value<String> kind,
  Value<bool> autoEnter,
  Value<int> sortOrder,
  required int updatedAt,
});
typedef $$SnippetsTableUpdateCompanionBuilder = SnippetsCompanion Function({
  Value<int> id,
  Value<String> uuid,
  Value<String> name,
  Value<String> content,
  Value<String> kind,
  Value<bool> autoEnter,
  Value<int> sortOrder,
  Value<int> updatedAt,
});

class $$SnippetsTableFilterComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoEnter => $composableBuilder(
    column: $table.autoEnter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SnippetsTableOrderingComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoEnter => $composableBuilder(
    column: $table.autoEnter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SnippetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SnippetsTable> {
  $$SnippetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get autoEnter =>
      $composableBuilder(column: $table.autoEnter, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SnippetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SnippetsTable,
          Snippet,
          $$SnippetsTableFilterComposer,
          $$SnippetsTableOrderingComposer,
          $$SnippetsTableAnnotationComposer,
          $$SnippetsTableCreateCompanionBuilder,
          $$SnippetsTableUpdateCompanionBuilder,
          (Snippet, BaseReferences<_$AppDatabase, $SnippetsTable, Snippet>),
          Snippet,
          PrefetchHooks Function()
        > {
  $$SnippetsTableTableManager(_$AppDatabase db, $SnippetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SnippetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SnippetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SnippetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<bool> autoEnter = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => SnippetsCompanion(
                id: id,
                uuid: uuid,
                name: name,
                content: content,
                kind: kind,
                autoEnter: autoEnter,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String name,
                Value<String> content = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<bool> autoEnter = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required int updatedAt,
              }) => SnippetsCompanion.insert(
                id: id,
                uuid: uuid,
                name: name,
                content: content,
                kind: kind,
                autoEnter: autoEnter,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SnippetsTable, Snippet>(table),
                  BaseReferences<_$AppDatabase, $SnippetsTable, Snippet>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SnippetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SnippetsTable,
      Snippet,
      $$SnippetsTableFilterComposer,
      $$SnippetsTableOrderingComposer,
      $$SnippetsTableAnnotationComposer,
      $$SnippetsTableCreateCompanionBuilder,
      $$SnippetsTableUpdateCompanionBuilder,
      (Snippet, BaseReferences<_$AppDatabase, $SnippetsTable, Snippet>),
      Snippet,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$AgentConfigsTableCreateCompanionBuilder =
    AgentConfigsCompanion Function({
      Value<int> id,
      required String uuid,
      required String name,
      required String kind,
      Value<String> command,
      Value<String> args,
      Value<String> endpoint,
      Value<String?> apiKeyEnc,
      Value<String> model,
      Value<String> systemPrompt,
      Value<bool> isActive,
      required int createdAt,
      Value<String> reasoningEffort,
    });
typedef $$AgentConfigsTableUpdateCompanionBuilder =
    AgentConfigsCompanion Function({
      Value<int> id,
      Value<String> uuid,
      Value<String> name,
      Value<String> kind,
      Value<String> command,
      Value<String> args,
      Value<String> endpoint,
      Value<String?> apiKeyEnc,
      Value<String> model,
      Value<String> systemPrompt,
      Value<bool> isActive,
      Value<int> createdAt,
      Value<String> reasoningEffort,
    });

class $$AgentConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $AgentConfigsTable> {
  $$AgentConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get args => $composableBuilder(
    column: $table.args,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get apiKeyEnc => $composableBuilder(
    column: $table.apiKeyEnc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AgentConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $AgentConfigsTable> {
  $$AgentConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get command => $composableBuilder(
    column: $table.command,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get args => $composableBuilder(
    column: $table.args,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get apiKeyEnc => $composableBuilder(
    column: $table.apiKeyEnc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AgentConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AgentConfigsTable> {
  $$AgentConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get command =>
      $composableBuilder(column: $table.command, builder: (column) => column);

  GeneratedColumn<String> get args =>
      $composableBuilder(column: $table.args, builder: (column) => column);

  GeneratedColumn<String> get endpoint =>
      $composableBuilder(column: $table.endpoint, builder: (column) => column);

  GeneratedColumn<String> get apiKeyEnc =>
      $composableBuilder(column: $table.apiKeyEnc, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get systemPrompt => $composableBuilder(
    column: $table.systemPrompt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get reasoningEffort => $composableBuilder(
    column: $table.reasoningEffort,
    builder: (column) => column,
  );
}

class $$AgentConfigsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AgentConfigsTable,
          AgentConfig,
          $$AgentConfigsTableFilterComposer,
          $$AgentConfigsTableOrderingComposer,
          $$AgentConfigsTableAnnotationComposer,
          $$AgentConfigsTableCreateCompanionBuilder,
          $$AgentConfigsTableUpdateCompanionBuilder,
          (
            AgentConfig,
            BaseReferences<_$AppDatabase, $AgentConfigsTable, AgentConfig>,
          ),
          AgentConfig,
          PrefetchHooks Function()
        > {
  $$AgentConfigsTableTableManager(_$AppDatabase db, $AgentConfigsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AgentConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AgentConfigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AgentConfigsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> command = const Value.absent(),
                Value<String> args = const Value.absent(),
                Value<String> endpoint = const Value.absent(),
                Value<String?> apiKeyEnc = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> systemPrompt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> reasoningEffort = const Value.absent(),
              }) => AgentConfigsCompanion(
                id: id,
                uuid: uuid,
                name: name,
                kind: kind,
                command: command,
                args: args,
                endpoint: endpoint,
                apiKeyEnc: apiKeyEnc,
                model: model,
                systemPrompt: systemPrompt,
                isActive: isActive,
                createdAt: createdAt,
                reasoningEffort: reasoningEffort,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String name,
                required String kind,
                Value<String> command = const Value.absent(),
                Value<String> args = const Value.absent(),
                Value<String> endpoint = const Value.absent(),
                Value<String?> apiKeyEnc = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> systemPrompt = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                required int createdAt,
                Value<String> reasoningEffort = const Value.absent(),
              }) => AgentConfigsCompanion.insert(
                id: id,
                uuid: uuid,
                name: name,
                kind: kind,
                command: command,
                args: args,
                endpoint: endpoint,
                apiKeyEnc: apiKeyEnc,
                model: model,
                systemPrompt: systemPrompt,
                isActive: isActive,
                createdAt: createdAt,
                reasoningEffort: reasoningEffort,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AgentConfigsTable, AgentConfig>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AgentConfigsTable,
                    AgentConfig
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AgentConfigsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AgentConfigsTable,
      AgentConfig,
      $$AgentConfigsTableFilterComposer,
      $$AgentConfigsTableOrderingComposer,
      $$AgentConfigsTableAnnotationComposer,
      $$AgentConfigsTableCreateCompanionBuilder,
      $$AgentConfigsTableUpdateCompanionBuilder,
      (
        AgentConfig,
        BaseReferences<_$AppDatabase, $AgentConfigsTable, AgentConfig>,
      ),
      AgentConfig,
      PrefetchHooks Function()
    >;
typedef $$ChatSessionsTableCreateCompanionBuilder =
    ChatSessionsCompanion Function({
      Value<int> id,
      required String uuid,
      required String title,
      required String agentUuid,
      required String agentName,
      Value<String> model,
      Value<String> hostName,
      Value<String?> externalSessionId,
      required int createdAt,
      required int updatedAt,
    });
typedef $$ChatSessionsTableUpdateCompanionBuilder =
    ChatSessionsCompanion Function({
      Value<int> id,
      Value<String> uuid,
      Value<String> title,
      Value<String> agentUuid,
      Value<String> agentName,
      Value<String> model,
      Value<String> hostName,
      Value<String?> externalSessionId,
      Value<int> createdAt,
      Value<int> updatedAt,
    });

class $$ChatSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentUuid => $composableBuilder(
    column: $table.agentUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostName => $composableBuilder(
    column: $table.hostName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get externalSessionId => $composableBuilder(
    column: $table.externalSessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentUuid => $composableBuilder(
    column: $table.agentUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostName => $composableBuilder(
    column: $table.hostName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get externalSessionId => $composableBuilder(
    column: $table.externalSessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatSessionsTable> {
  $$ChatSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get agentUuid =>
      $composableBuilder(column: $table.agentUuid, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get hostName =>
      $composableBuilder(column: $table.hostName, builder: (column) => column);

  GeneratedColumn<String> get externalSessionId => $composableBuilder(
    column: $table.externalSessionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ChatSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatSessionsTable,
          ChatSession,
          $$ChatSessionsTableFilterComposer,
          $$ChatSessionsTableOrderingComposer,
          $$ChatSessionsTableAnnotationComposer,
          $$ChatSessionsTableCreateCompanionBuilder,
          $$ChatSessionsTableUpdateCompanionBuilder,
          (
            ChatSession,
            BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSession>,
          ),
          ChatSession,
          PrefetchHooks Function()
        > {
  $$ChatSessionsTableTableManager(_$AppDatabase db, $ChatSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> agentUuid = const Value.absent(),
                Value<String> agentName = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> hostName = const Value.absent(),
                Value<String?> externalSessionId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => ChatSessionsCompanion(
                id: id,
                uuid: uuid,
                title: title,
                agentUuid: agentUuid,
                agentName: agentName,
                model: model,
                hostName: hostName,
                externalSessionId: externalSessionId,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String title,
                required String agentUuid,
                required String agentName,
                Value<String> model = const Value.absent(),
                Value<String> hostName = const Value.absent(),
                Value<String?> externalSessionId = const Value.absent(),
                required int createdAt,
                required int updatedAt,
              }) => ChatSessionsCompanion.insert(
                id: id,
                uuid: uuid,
                title: title,
                agentUuid: agentUuid,
                agentName: agentName,
                model: model,
                hostName: hostName,
                externalSessionId: externalSessionId,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatSessionsTable, ChatSession>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatSessionsTable,
                    ChatSession
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatSessionsTable,
      ChatSession,
      $$ChatSessionsTableFilterComposer,
      $$ChatSessionsTableOrderingComposer,
      $$ChatSessionsTableAnnotationComposer,
      $$ChatSessionsTableCreateCompanionBuilder,
      $$ChatSessionsTableUpdateCompanionBuilder,
      (
        ChatSession,
        BaseReferences<_$AppDatabase, $ChatSessionsTable, ChatSession>,
      ),
      ChatSession,
      PrefetchHooks Function()
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      required int sessionId,
      required String role,
      required String content,
      Value<int> inputTokens,
      Value<int> outputTokens,
      required int createdAt,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      Value<int> sessionId,
      Value<String> role,
      Value<String> content,
      Value<int> inputTokens,
      Value<int> outputTokens,
      Value<int> createdAt,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatMessagesTable,
          ChatMessage,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            ChatMessage,
            BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessage>,
          ),
          ChatMessage,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$AppDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sessionId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> inputTokens = const Value.absent(),
                Value<int> outputTokens = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                sessionId: sessionId,
                role: role,
                content: content,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sessionId,
                required String role,
                required String content,
                Value<int> inputTokens = const Value.absent(),
                Value<int> outputTokens = const Value.absent(),
                required int createdAt,
              }) => ChatMessagesCompanion.insert(
                id: id,
                sessionId: sessionId,
                role: role,
                content: content,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatMessagesTable, ChatMessage>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatMessagesTable,
                    ChatMessage
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatMessagesTable,
      ChatMessage,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        ChatMessage,
        BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessage>,
      ),
      ChatMessage,
      PrefetchHooks Function()
    >;
typedef $$TokenUsagesTableCreateCompanionBuilder =
    TokenUsagesCompanion Function({
      Value<int> id,
      required String day,
      required String agentUuid,
      required String agentName,
      required String model,
      required int inputTokens,
      required int outputTokens,
      required int createdAt,
    });
typedef $$TokenUsagesTableUpdateCompanionBuilder =
    TokenUsagesCompanion Function({
      Value<int> id,
      Value<String> day,
      Value<String> agentUuid,
      Value<String> agentName,
      Value<String> model,
      Value<int> inputTokens,
      Value<int> outputTokens,
      Value<int> createdAt,
    });

class $$TokenUsagesTableFilterComposer
    extends Composer<_$AppDatabase, $TokenUsagesTable> {
  $$TokenUsagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentUuid => $composableBuilder(
    column: $table.agentUuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TokenUsagesTableOrderingComposer
    extends Composer<_$AppDatabase, $TokenUsagesTable> {
  $$TokenUsagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentUuid => $composableBuilder(
    column: $table.agentUuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get agentName => $composableBuilder(
    column: $table.agentName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TokenUsagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TokenUsagesTable> {
  $$TokenUsagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get agentUuid =>
      $composableBuilder(column: $table.agentUuid, builder: (column) => column);

  GeneratedColumn<String> get agentName =>
      $composableBuilder(column: $table.agentName, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get inputTokens => $composableBuilder(
    column: $table.inputTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get outputTokens => $composableBuilder(
    column: $table.outputTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TokenUsagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TokenUsagesTable,
          TokenUsage,
          $$TokenUsagesTableFilterComposer,
          $$TokenUsagesTableOrderingComposer,
          $$TokenUsagesTableAnnotationComposer,
          $$TokenUsagesTableCreateCompanionBuilder,
          $$TokenUsagesTableUpdateCompanionBuilder,
          (
            TokenUsage,
            BaseReferences<_$AppDatabase, $TokenUsagesTable, TokenUsage>,
          ),
          TokenUsage,
          PrefetchHooks Function()
        > {
  $$TokenUsagesTableTableManager(_$AppDatabase db, $TokenUsagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TokenUsagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TokenUsagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TokenUsagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<String> agentUuid = const Value.absent(),
                Value<String> agentName = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> inputTokens = const Value.absent(),
                Value<int> outputTokens = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => TokenUsagesCompanion(
                id: id,
                day: day,
                agentUuid: agentUuid,
                agentName: agentName,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String day,
                required String agentUuid,
                required String agentName,
                required String model,
                required int inputTokens,
                required int outputTokens,
                required int createdAt,
              }) => TokenUsagesCompanion.insert(
                id: id,
                day: day,
                agentUuid: agentUuid,
                agentName: agentName,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TokenUsagesTable, TokenUsage>(table),
                  BaseReferences<_$AppDatabase, $TokenUsagesTable, TokenUsage>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TokenUsagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TokenUsagesTable,
      TokenUsage,
      $$TokenUsagesTableFilterComposer,
      $$TokenUsagesTableOrderingComposer,
      $$TokenUsagesTableAnnotationComposer,
      $$TokenUsagesTableCreateCompanionBuilder,
      $$TokenUsagesTableUpdateCompanionBuilder,
      (
        TokenUsage,
        BaseReferences<_$AppDatabase, $TokenUsagesTable, TokenUsage>,
      ),
      TokenUsage,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$HostGroupsTableTableManager get hostGroups =>
      $$HostGroupsTableTableManager(_db, _db.hostGroups);
  $$HostsTableTableManager get hosts =>
      $$HostsTableTableManager(_db, _db.hosts);
  $$SshKeysTableTableManager get sshKeys =>
      $$SshKeysTableTableManager(_db, _db.sshKeys);
  $$SnippetsTableTableManager get snippets =>
      $$SnippetsTableTableManager(_db, _db.snippets);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$AgentConfigsTableTableManager get agentConfigs =>
      $$AgentConfigsTableTableManager(_db, _db.agentConfigs);
  $$ChatSessionsTableTableManager get chatSessions =>
      $$ChatSessionsTableTableManager(_db, _db.chatSessions);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$TokenUsagesTableTableManager get tokenUsages =>
      $$TokenUsagesTableTableManager(_db, _db.tokenUsages);
}
