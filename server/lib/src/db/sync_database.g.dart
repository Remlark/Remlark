// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_database.dart';

// ignore_for_file: type=lint
class $SyncItemsTable extends SyncItems with TableInfo<$SyncItemsTable, SyncItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'),
  );
  static const VerificationMeta _spaceMeta = const VerificationMeta('space');
  @override
  late final GeneratedColumn<String> space = GeneratedColumn<String>(
    'space',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta('deleted');
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("deleted" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [id, space, uuid, updatedAt, deleted, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_items';
  @override
  VerificationContext validateIntegrity(Insertable<SyncItem> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('space')) {
      context.handle(_spaceMeta, space.isAcceptableOrUnknown(data['space']!, _spaceMeta));
    } else if (isInserting) {
      context.missing(_spaceMeta);
    }
    if (data.containsKey('uuid')) {
      context.handle(_uuidMeta, uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta));
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta, updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(_deletedMeta, deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta));
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta, payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncItem(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      space: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}space'])!,
      uuid: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}uuid'])!,
      updatedAt: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deleted: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}deleted'])!,
      payload: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
    );
  }

  @override
  $SyncItemsTable createAlias(String alias) {
    return $SyncItemsTable(attachedDatabase, alias);
  }
}

class SyncItem extends DataClass implements Insertable<SyncItem> {
  final int id;

  /// 数据空间 id（访问令牌的 SHA-256 前缀）
  final String space;
  final String uuid;

  /// 客户端提供的最后更新时间（毫秒）
  final int updatedAt;

  /// 删除标记：被删除的条目保留标记，供其他客户端停止同步
  final bool deleted;

  /// 客户端加密后的载荷（服务端无法解密）
  final String payload;
  const SyncItem({
    required this.id,
    required this.space,
    required this.uuid,
    required this.updatedAt,
    required this.deleted,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['space'] = Variable<String>(space);
    map['uuid'] = Variable<String>(uuid);
    map['updated_at'] = Variable<int>(updatedAt);
    map['deleted'] = Variable<bool>(deleted);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  SyncItemsCompanion toCompanion(bool nullToAbsent) {
    return SyncItemsCompanion(
      id: Value(id),
      space: Value(space),
      uuid: Value(uuid),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      payload: Value(payload),
    );
  }

  factory SyncItem.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncItem(
      id: serializer.fromJson<int>(json['id']),
      space: serializer.fromJson<String>(json['space']),
      uuid: serializer.fromJson<String>(json['uuid']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'space': serializer.toJson<String>(space),
      'uuid': serializer.toJson<String>(uuid),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deleted': serializer.toJson<bool>(deleted),
      'payload': serializer.toJson<String>(payload),
    };
  }

  SyncItem copyWith({int? id, String? space, String? uuid, int? updatedAt, bool? deleted, String? payload}) => SyncItem(
    id: id ?? this.id,
    space: space ?? this.space,
    uuid: uuid ?? this.uuid,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
    payload: payload ?? this.payload,
  );
  SyncItem copyWithCompanion(SyncItemsCompanion data) {
    return SyncItem(
      id: data.id.present ? data.id.value : this.id,
      space: data.space.present ? data.space.value : this.space,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncItem(')
          ..write('id: $id, ')
          ..write('space: $space, ')
          ..write('uuid: $uuid, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, space, uuid, updatedAt, deleted, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncItem &&
          other.id == this.id &&
          other.space == this.space &&
          other.uuid == this.uuid &&
          other.updatedAt == this.updatedAt &&
          other.deleted == this.deleted &&
          other.payload == this.payload);
}

class SyncItemsCompanion extends UpdateCompanion<SyncItem> {
  final Value<int> id;
  final Value<String> space;
  final Value<String> uuid;
  final Value<int> updatedAt;
  final Value<bool> deleted;
  final Value<String> payload;
  const SyncItemsCompanion({
    this.id = const Value.absent(),
    this.space = const Value.absent(),
    this.uuid = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.payload = const Value.absent(),
  });
  SyncItemsCompanion.insert({
    this.id = const Value.absent(),
    required String space,
    required String uuid,
    required int updatedAt,
    this.deleted = const Value.absent(),
    this.payload = const Value.absent(),
  }) : space = Value(space),
       uuid = Value(uuid),
       updatedAt = Value(updatedAt);
  static Insertable<SyncItem> custom({
    Expression<int>? id,
    Expression<String>? space,
    Expression<String>? uuid,
    Expression<int>? updatedAt,
    Expression<bool>? deleted,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (space != null) 'space': space,
      if (uuid != null) 'uuid': uuid,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deleted != null) 'deleted': deleted,
      if (payload != null) 'payload': payload,
    });
  }

  SyncItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? space,
    Value<String>? uuid,
    Value<int>? updatedAt,
    Value<bool>? deleted,
    Value<String>? payload,
  }) {
    return SyncItemsCompanion(
      id: id ?? this.id,
      space: space ?? this.space,
      uuid: uuid ?? this.uuid,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (space.present) {
      map['space'] = Variable<String>(space.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncItemsCompanion(')
          ..write('id: $id, ')
          ..write('space: $space, ')
          ..write('uuid: $uuid, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

abstract class _$SyncDatabase extends GeneratedDatabase {
  _$SyncDatabase(QueryExecutor e) : super(e);
  $SyncDatabaseManager get managers => $SyncDatabaseManager(this);
  late final $SyncItemsTable syncItems = $SyncItemsTable(this);
  late final Index idxItemsSpaceUuid = Index(
    'idx_items_space_uuid',
    'CREATE UNIQUE INDEX idx_items_space_uuid ON sync_items (space, uuid)',
  );
  late final Index idxItemsSpaceUpdated = Index(
    'idx_items_space_updated',
    'CREATE INDEX idx_items_space_updated ON sync_items (space, updated_at)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [syncItems, idxItemsSpaceUuid, idxItemsSpaceUpdated];
}

typedef $$SyncItemsTableCreateCompanionBuilder =
    SyncItemsCompanion Function({
      Value<int> id,
      required String space,
      required String uuid,
      required int updatedAt,
      Value<bool> deleted,
      Value<String> payload,
    });
typedef $$SyncItemsTableUpdateCompanionBuilder =
    SyncItemsCompanion Function({
      Value<int> id,
      Value<String> space,
      Value<String> uuid,
      Value<int> updatedAt,
      Value<bool> deleted,
      Value<String> payload,
    });

class $$SyncItemsTableFilterComposer extends Composer<_$SyncDatabase, $SyncItemsTable> {
  $$SyncItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get space =>
      $composableBuilder(column: $table.space, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uuid => $composableBuilder(column: $table.uuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnFilters(column));
}

class $$SyncItemsTableOrderingComposer extends Composer<_$SyncDatabase, $SyncItemsTable> {
  $$SyncItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get space =>
      $composableBuilder(column: $table.space, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => ColumnOrderings(column));
}

class $$SyncItemsTableAnnotationComposer extends Composer<_$SyncDatabase, $SyncItemsTable> {
  $$SyncItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get space => $composableBuilder(column: $table.space, builder: (column) => column);

  GeneratedColumn<String> get uuid => $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<int> get updatedAt => $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted => $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get payload => $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$SyncItemsTableTableManager
    extends
        RootTableManager<
          _$SyncDatabase,
          $SyncItemsTable,
          SyncItem,
          $$SyncItemsTableFilterComposer,
          $$SyncItemsTableOrderingComposer,
          $$SyncItemsTableAnnotationComposer,
          $$SyncItemsTableCreateCompanionBuilder,
          $$SyncItemsTableUpdateCompanionBuilder,
          (SyncItem, BaseReferences<_$SyncDatabase, $SyncItemsTable, SyncItem>),
          SyncItem,
          PrefetchHooks Function()
        > {
  $$SyncItemsTableTableManager(_$SyncDatabase db, $SyncItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$SyncItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$SyncItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$SyncItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> space = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> payload = const Value.absent(),
              }) => SyncItemsCompanion(
                id: id,
                space: space,
                uuid: uuid,
                updatedAt: updatedAt,
                deleted: deleted,
                payload: payload,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String space,
                required String uuid,
                required int updatedAt,
                Value<bool> deleted = const Value.absent(),
                Value<String> payload = const Value.absent(),
              }) => SyncItemsCompanion.insert(
                id: id,
                space: space,
                uuid: uuid,
                updatedAt: updatedAt,
                deleted: deleted,
                payload: payload,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncItemsTable, SyncItem>(table),
                  BaseReferences<_$SyncDatabase, $SyncItemsTable, SyncItem>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$SyncDatabase,
      $SyncItemsTable,
      SyncItem,
      $$SyncItemsTableFilterComposer,
      $$SyncItemsTableOrderingComposer,
      $$SyncItemsTableAnnotationComposer,
      $$SyncItemsTableCreateCompanionBuilder,
      $$SyncItemsTableUpdateCompanionBuilder,
      (SyncItem, BaseReferences<_$SyncDatabase, $SyncItemsTable, SyncItem>),
      SyncItem,
      PrefetchHooks Function()
    >;

class $SyncDatabaseManager {
  final _$SyncDatabase _db;
  $SyncDatabaseManager(this._db);
  $$SyncItemsTableTableManager get syncItems => $$SyncItemsTableTableManager(_db, _db.syncItems);
}
