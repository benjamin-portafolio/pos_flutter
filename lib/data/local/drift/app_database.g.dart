// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdEventIdMeta = const VerificationMeta(
    'createdEventId',
  );
  @override
  late final GeneratedColumn<String> createdEventId = GeneratedColumn<String>(
    'created_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastEventIdMeta = const VerificationMeta(
    'lastEventId',
  );
  @override
  late final GeneratedColumn<String> lastEventId = GeneratedColumn<String>(
    'last_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastServerSequenceMeta =
      const VerificationMeta('lastServerSequence');
  @override
  late final GeneratedColumn<int> lastServerSequence = GeneratedColumn<int>(
    'last_server_sequence',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
  static const VerificationMeta _colorKeyMeta = const VerificationMeta(
    'colorKey',
  );
  @override
  late final GeneratedColumn<String> colorKey = GeneratedColumn<String>(
    'color_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('neutral'),
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    active,
    version,
    createdEventId,
    lastEventId,
    lastServerSequence,
    name,
    colorKey,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('created_event_id')) {
      context.handle(
        _createdEventIdMeta,
        createdEventId.isAcceptableOrUnknown(
          data['created_event_id']!,
          _createdEventIdMeta,
        ),
      );
    }
    if (data.containsKey('last_event_id')) {
      context.handle(
        _lastEventIdMeta,
        lastEventId.isAcceptableOrUnknown(
          data['last_event_id']!,
          _lastEventIdMeta,
        ),
      );
    }
    if (data.containsKey('last_server_sequence')) {
      context.handle(
        _lastServerSequenceMeta,
        lastServerSequence.isAcceptableOrUnknown(
          data['last_server_sequence']!,
          _lastServerSequenceMeta,
        ),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_key')) {
      context.handle(
        _colorKeyMeta,
        colorKey.isAcceptableOrUnknown(data['color_key']!, _colorKeyMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_event_id'],
      ),
      lastEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_event_id'],
      ),
      lastServerSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_server_sequence'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_key'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  /// Unique global ID generated on the device as a UUID
  final String id;

  /// Logical deletion flag (active = true means not deleted)
  final bool active;

  /// Version for optimistic concurrency control and conflict resolution
  final int version;

  /// Reference to the event that created this record
  final String? createdEventId;

  /// Reference to the last event that modified this record
  final String? lastEventId;

  /// Sync cursor representing the official server sequence
  final int? lastServerSequence;

  /// Nombre visible de la categoria en la gestion de inventario y articulos.
  final String name;

  /// Clave estable del color que la interfaz usara para representar la categoria.
  final String colorKey;

  /// Posicion consecutiva de la categoria en los listados, comenzando en cero.
  final int sortOrder;
  const CategoryRow({
    required this.id,
    required this.active,
    required this.version,
    this.createdEventId,
    this.lastEventId,
    this.lastServerSequence,
    required this.name,
    required this.colorKey,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['active'] = Variable<bool>(active);
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || createdEventId != null) {
      map['created_event_id'] = Variable<String>(createdEventId);
    }
    if (!nullToAbsent || lastEventId != null) {
      map['last_event_id'] = Variable<String>(lastEventId);
    }
    if (!nullToAbsent || lastServerSequence != null) {
      map['last_server_sequence'] = Variable<int>(lastServerSequence);
    }
    map['name'] = Variable<String>(name);
    map['color_key'] = Variable<String>(colorKey);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      active: Value(active),
      version: Value(version),
      createdEventId: createdEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(createdEventId),
      lastEventId: lastEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastEventId),
      lastServerSequence: lastServerSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(lastServerSequence),
      name: Value(name),
      colorKey: Value(colorKey),
      sortOrder: Value(sortOrder),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      id: serializer.fromJson<String>(json['id']),
      active: serializer.fromJson<bool>(json['active']),
      version: serializer.fromJson<int>(json['version']),
      createdEventId: serializer.fromJson<String?>(json['createdEventId']),
      lastEventId: serializer.fromJson<String?>(json['lastEventId']),
      lastServerSequence: serializer.fromJson<int?>(json['lastServerSequence']),
      name: serializer.fromJson<String>(json['name']),
      colorKey: serializer.fromJson<String>(json['colorKey']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'active': serializer.toJson<bool>(active),
      'version': serializer.toJson<int>(version),
      'createdEventId': serializer.toJson<String?>(createdEventId),
      'lastEventId': serializer.toJson<String?>(lastEventId),
      'lastServerSequence': serializer.toJson<int?>(lastServerSequence),
      'name': serializer.toJson<String>(name),
      'colorKey': serializer.toJson<String>(colorKey),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  CategoryRow copyWith({
    String? id,
    bool? active,
    int? version,
    Value<String?> createdEventId = const Value.absent(),
    Value<String?> lastEventId = const Value.absent(),
    Value<int?> lastServerSequence = const Value.absent(),
    String? name,
    String? colorKey,
    int? sortOrder,
  }) => CategoryRow(
    id: id ?? this.id,
    active: active ?? this.active,
    version: version ?? this.version,
    createdEventId: createdEventId.present
        ? createdEventId.value
        : this.createdEventId,
    lastEventId: lastEventId.present ? lastEventId.value : this.lastEventId,
    lastServerSequence: lastServerSequence.present
        ? lastServerSequence.value
        : this.lastServerSequence,
    name: name ?? this.name,
    colorKey: colorKey ?? this.colorKey,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      id: data.id.present ? data.id.value : this.id,
      active: data.active.present ? data.active.value : this.active,
      version: data.version.present ? data.version.value : this.version,
      createdEventId: data.createdEventId.present
          ? data.createdEventId.value
          : this.createdEventId,
      lastEventId: data.lastEventId.present
          ? data.lastEventId.value
          : this.lastEventId,
      lastServerSequence: data.lastServerSequence.present
          ? data.lastServerSequence.value
          : this.lastServerSequence,
      name: data.name.present ? data.name.value : this.name,
      colorKey: data.colorKey.present ? data.colorKey.value : this.colorKey,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('name: $name, ')
          ..write('colorKey: $colorKey, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    active,
    version,
    createdEventId,
    lastEventId,
    lastServerSequence,
    name,
    colorKey,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.id == this.id &&
          other.active == this.active &&
          other.version == this.version &&
          other.createdEventId == this.createdEventId &&
          other.lastEventId == this.lastEventId &&
          other.lastServerSequence == this.lastServerSequence &&
          other.name == this.name &&
          other.colorKey == this.colorKey &&
          other.sortOrder == this.sortOrder);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> id;
  final Value<bool> active;
  final Value<int> version;
  final Value<String?> createdEventId;
  final Value<String?> lastEventId;
  final Value<int?> lastServerSequence;
  final Value<String> name;
  final Value<String> colorKey;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    this.name = const Value.absent(),
    this.colorKey = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    required String name,
    this.colorKey = const Value.absent(),
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       sortOrder = Value(sortOrder);
  static Insertable<CategoryRow> custom({
    Expression<String>? id,
    Expression<bool>? active,
    Expression<int>? version,
    Expression<String>? createdEventId,
    Expression<String>? lastEventId,
    Expression<int>? lastServerSequence,
    Expression<String>? name,
    Expression<String>? colorKey,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (active != null) 'active': active,
      if (version != null) 'version': version,
      if (createdEventId != null) 'created_event_id': createdEventId,
      if (lastEventId != null) 'last_event_id': lastEventId,
      if (lastServerSequence != null)
        'last_server_sequence': lastServerSequence,
      if (name != null) 'name': name,
      if (colorKey != null) 'color_key': colorKey,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<bool>? active,
    Value<int>? version,
    Value<String?>? createdEventId,
    Value<String?>? lastEventId,
    Value<int?>? lastServerSequence,
    Value<String>? name,
    Value<String>? colorKey,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      active: active ?? this.active,
      version: version ?? this.version,
      createdEventId: createdEventId ?? this.createdEventId,
      lastEventId: lastEventId ?? this.lastEventId,
      lastServerSequence: lastServerSequence ?? this.lastServerSequence,
      name: name ?? this.name,
      colorKey: colorKey ?? this.colorKey,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdEventId.present) {
      map['created_event_id'] = Variable<String>(createdEventId.value);
    }
    if (lastEventId.present) {
      map['last_event_id'] = Variable<String>(lastEventId.value);
    }
    if (lastServerSequence.present) {
      map['last_server_sequence'] = Variable<int>(lastServerSequence.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorKey.present) {
      map['color_key'] = Variable<String>(colorKey.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('name: $name, ')
          ..write('colorKey: $colorKey, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EspaciosTable extends Espacios with TableInfo<$EspaciosTable, Espacio> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EspaciosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _createdEventIdMeta = const VerificationMeta(
    'createdEventId',
  );
  @override
  late final GeneratedColumn<String> createdEventId = GeneratedColumn<String>(
    'created_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastEventIdMeta = const VerificationMeta(
    'lastEventId',
  );
  @override
  late final GeneratedColumn<String> lastEventId = GeneratedColumn<String>(
    'last_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastServerSequenceMeta =
      const VerificationMeta('lastServerSequence');
  @override
  late final GeneratedColumn<int> lastServerSequence = GeneratedColumn<int>(
    'last_server_sequence',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nombreMeta = const VerificationMeta('nombre');
  @override
  late final GeneratedColumn<String> nombre = GeneratedColumn<String>(
    'nombre',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identificacionMeta = const VerificationMeta(
    'identificacion',
  );
  @override
  late final GeneratedColumn<String> identificacion = GeneratedColumn<String>(
    'identificacion',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<VisibilidadEspacio, int>
  visibilidad = GeneratedColumn<int>(
    'visibilidad',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  ).withConverter<VisibilidadEspacio>($EspaciosTable.$convertervisibilidad);
  @override
  List<GeneratedColumn> get $columns => [
    id,
    active,
    version,
    createdEventId,
    lastEventId,
    lastServerSequence,
    nombre,
    identificacion,
    visibilidad,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'espacios';
  @override
  VerificationContext validateIntegrity(
    Insertable<Espacio> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('created_event_id')) {
      context.handle(
        _createdEventIdMeta,
        createdEventId.isAcceptableOrUnknown(
          data['created_event_id']!,
          _createdEventIdMeta,
        ),
      );
    }
    if (data.containsKey('last_event_id')) {
      context.handle(
        _lastEventIdMeta,
        lastEventId.isAcceptableOrUnknown(
          data['last_event_id']!,
          _lastEventIdMeta,
        ),
      );
    }
    if (data.containsKey('last_server_sequence')) {
      context.handle(
        _lastServerSequenceMeta,
        lastServerSequence.isAcceptableOrUnknown(
          data['last_server_sequence']!,
          _lastServerSequenceMeta,
        ),
      );
    }
    if (data.containsKey('nombre')) {
      context.handle(
        _nombreMeta,
        nombre.isAcceptableOrUnknown(data['nombre']!, _nombreMeta),
      );
    } else if (isInserting) {
      context.missing(_nombreMeta);
    }
    if (data.containsKey('identificacion')) {
      context.handle(
        _identificacionMeta,
        identificacion.isAcceptableOrUnknown(
          data['identificacion']!,
          _identificacionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Espacio map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Espacio(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      createdEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_event_id'],
      ),
      lastEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_event_id'],
      ),
      lastServerSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_server_sequence'],
      ),
      nombre: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nombre'],
      )!,
      identificacion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identificacion'],
      ),
      visibilidad: $EspaciosTable.$convertervisibilidad.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}visibilidad'],
        )!,
      ),
    );
  }

  @override
  $EspaciosTable createAlias(String alias) {
    return $EspaciosTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<VisibilidadEspacio, int, int>
  $convertervisibilidad = const EnumIndexConverter<VisibilidadEspacio>(
    VisibilidadEspacio.values,
  );
}

class Espacio extends DataClass implements Insertable<Espacio> {
  /// Unique global ID generated on the device as a UUID
  final String id;

  /// Logical deletion flag (active = true means not deleted)
  final bool active;

  /// Version for optimistic concurrency control and conflict resolution
  final int version;

  /// Reference to the event that created this record
  final String? createdEventId;

  /// Reference to the last event that modified this record
  final String? lastEventId;

  /// Sync cursor representing the official server sequence
  final int? lastServerSequence;

  /// Nombre legible del espacio (ej. 'Terraza', 'Bar')
  final String nombre;

  /// Identificador único provisto por el usuario para fines de negocio (ej. 'piso_1')
  final String? identificacion;

  /// Nivel de visibilidad/restricción de artículos en este espacio
  final VisibilidadEspacio visibilidad;
  const Espacio({
    required this.id,
    required this.active,
    required this.version,
    this.createdEventId,
    this.lastEventId,
    this.lastServerSequence,
    required this.nombre,
    this.identificacion,
    required this.visibilidad,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['active'] = Variable<bool>(active);
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || createdEventId != null) {
      map['created_event_id'] = Variable<String>(createdEventId);
    }
    if (!nullToAbsent || lastEventId != null) {
      map['last_event_id'] = Variable<String>(lastEventId);
    }
    if (!nullToAbsent || lastServerSequence != null) {
      map['last_server_sequence'] = Variable<int>(lastServerSequence);
    }
    map['nombre'] = Variable<String>(nombre);
    if (!nullToAbsent || identificacion != null) {
      map['identificacion'] = Variable<String>(identificacion);
    }
    {
      map['visibilidad'] = Variable<int>(
        $EspaciosTable.$convertervisibilidad.toSql(visibilidad),
      );
    }
    return map;
  }

  EspaciosCompanion toCompanion(bool nullToAbsent) {
    return EspaciosCompanion(
      id: Value(id),
      active: Value(active),
      version: Value(version),
      createdEventId: createdEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(createdEventId),
      lastEventId: lastEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastEventId),
      lastServerSequence: lastServerSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(lastServerSequence),
      nombre: Value(nombre),
      identificacion: identificacion == null && nullToAbsent
          ? const Value.absent()
          : Value(identificacion),
      visibilidad: Value(visibilidad),
    );
  }

  factory Espacio.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Espacio(
      id: serializer.fromJson<String>(json['id']),
      active: serializer.fromJson<bool>(json['active']),
      version: serializer.fromJson<int>(json['version']),
      createdEventId: serializer.fromJson<String?>(json['createdEventId']),
      lastEventId: serializer.fromJson<String?>(json['lastEventId']),
      lastServerSequence: serializer.fromJson<int?>(json['lastServerSequence']),
      nombre: serializer.fromJson<String>(json['nombre']),
      identificacion: serializer.fromJson<String?>(json['identificacion']),
      visibilidad: $EspaciosTable.$convertervisibilidad.fromJson(
        serializer.fromJson<int>(json['visibilidad']),
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'active': serializer.toJson<bool>(active),
      'version': serializer.toJson<int>(version),
      'createdEventId': serializer.toJson<String?>(createdEventId),
      'lastEventId': serializer.toJson<String?>(lastEventId),
      'lastServerSequence': serializer.toJson<int?>(lastServerSequence),
      'nombre': serializer.toJson<String>(nombre),
      'identificacion': serializer.toJson<String?>(identificacion),
      'visibilidad': serializer.toJson<int>(
        $EspaciosTable.$convertervisibilidad.toJson(visibilidad),
      ),
    };
  }

  Espacio copyWith({
    String? id,
    bool? active,
    int? version,
    Value<String?> createdEventId = const Value.absent(),
    Value<String?> lastEventId = const Value.absent(),
    Value<int?> lastServerSequence = const Value.absent(),
    String? nombre,
    Value<String?> identificacion = const Value.absent(),
    VisibilidadEspacio? visibilidad,
  }) => Espacio(
    id: id ?? this.id,
    active: active ?? this.active,
    version: version ?? this.version,
    createdEventId: createdEventId.present
        ? createdEventId.value
        : this.createdEventId,
    lastEventId: lastEventId.present ? lastEventId.value : this.lastEventId,
    lastServerSequence: lastServerSequence.present
        ? lastServerSequence.value
        : this.lastServerSequence,
    nombre: nombre ?? this.nombre,
    identificacion: identificacion.present
        ? identificacion.value
        : this.identificacion,
    visibilidad: visibilidad ?? this.visibilidad,
  );
  Espacio copyWithCompanion(EspaciosCompanion data) {
    return Espacio(
      id: data.id.present ? data.id.value : this.id,
      active: data.active.present ? data.active.value : this.active,
      version: data.version.present ? data.version.value : this.version,
      createdEventId: data.createdEventId.present
          ? data.createdEventId.value
          : this.createdEventId,
      lastEventId: data.lastEventId.present
          ? data.lastEventId.value
          : this.lastEventId,
      lastServerSequence: data.lastServerSequence.present
          ? data.lastServerSequence.value
          : this.lastServerSequence,
      nombre: data.nombre.present ? data.nombre.value : this.nombre,
      identificacion: data.identificacion.present
          ? data.identificacion.value
          : this.identificacion,
      visibilidad: data.visibilidad.present
          ? data.visibilidad.value
          : this.visibilidad,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Espacio(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('nombre: $nombre, ')
          ..write('identificacion: $identificacion, ')
          ..write('visibilidad: $visibilidad')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    active,
    version,
    createdEventId,
    lastEventId,
    lastServerSequence,
    nombre,
    identificacion,
    visibilidad,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Espacio &&
          other.id == this.id &&
          other.active == this.active &&
          other.version == this.version &&
          other.createdEventId == this.createdEventId &&
          other.lastEventId == this.lastEventId &&
          other.lastServerSequence == this.lastServerSequence &&
          other.nombre == this.nombre &&
          other.identificacion == this.identificacion &&
          other.visibilidad == this.visibilidad);
}

class EspaciosCompanion extends UpdateCompanion<Espacio> {
  final Value<String> id;
  final Value<bool> active;
  final Value<int> version;
  final Value<String?> createdEventId;
  final Value<String?> lastEventId;
  final Value<int?> lastServerSequence;
  final Value<String> nombre;
  final Value<String?> identificacion;
  final Value<VisibilidadEspacio> visibilidad;
  final Value<int> rowid;
  const EspaciosCompanion({
    this.id = const Value.absent(),
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    this.nombre = const Value.absent(),
    this.identificacion = const Value.absent(),
    this.visibilidad = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EspaciosCompanion.insert({
    required String id,
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    required String nombre,
    this.identificacion = const Value.absent(),
    required VisibilidadEspacio visibilidad,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       nombre = Value(nombre),
       visibilidad = Value(visibilidad);
  static Insertable<Espacio> custom({
    Expression<String>? id,
    Expression<bool>? active,
    Expression<int>? version,
    Expression<String>? createdEventId,
    Expression<String>? lastEventId,
    Expression<int>? lastServerSequence,
    Expression<String>? nombre,
    Expression<String>? identificacion,
    Expression<int>? visibilidad,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (active != null) 'active': active,
      if (version != null) 'version': version,
      if (createdEventId != null) 'created_event_id': createdEventId,
      if (lastEventId != null) 'last_event_id': lastEventId,
      if (lastServerSequence != null)
        'last_server_sequence': lastServerSequence,
      if (nombre != null) 'nombre': nombre,
      if (identificacion != null) 'identificacion': identificacion,
      if (visibilidad != null) 'visibilidad': visibilidad,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EspaciosCompanion copyWith({
    Value<String>? id,
    Value<bool>? active,
    Value<int>? version,
    Value<String?>? createdEventId,
    Value<String?>? lastEventId,
    Value<int?>? lastServerSequence,
    Value<String>? nombre,
    Value<String?>? identificacion,
    Value<VisibilidadEspacio>? visibilidad,
    Value<int>? rowid,
  }) {
    return EspaciosCompanion(
      id: id ?? this.id,
      active: active ?? this.active,
      version: version ?? this.version,
      createdEventId: createdEventId ?? this.createdEventId,
      lastEventId: lastEventId ?? this.lastEventId,
      lastServerSequence: lastServerSequence ?? this.lastServerSequence,
      nombre: nombre ?? this.nombre,
      identificacion: identificacion ?? this.identificacion,
      visibilidad: visibilidad ?? this.visibilidad,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (createdEventId.present) {
      map['created_event_id'] = Variable<String>(createdEventId.value);
    }
    if (lastEventId.present) {
      map['last_event_id'] = Variable<String>(lastEventId.value);
    }
    if (lastServerSequence.present) {
      map['last_server_sequence'] = Variable<int>(lastServerSequence.value);
    }
    if (nombre.present) {
      map['nombre'] = Variable<String>(nombre.value);
    }
    if (identificacion.present) {
      map['identificacion'] = Variable<String>(identificacion.value);
    }
    if (visibilidad.present) {
      map['visibilidad'] = Variable<int>(
        $EspaciosTable.$convertervisibilidad.toSql(visibilidad.value),
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EspaciosCompanion(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('nombre: $nombre, ')
          ..write('identificacion: $identificacion, ')
          ..write('visibilidad: $visibilidad, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, EventRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateTypeMeta = const VerificationMeta(
    'aggregateType',
  );
  @override
  late final GeneratedColumn<String> aggregateType = GeneratedColumn<String>(
    'aggregate_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localSequenceMeta = const VerificationMeta(
    'localSequence',
  );
  @override
  late final GeneratedColumn<int> localSequence = GeneratedColumn<int>(
    'local_sequence',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _serverSequenceMeta = const VerificationMeta(
    'serverSequence',
  );
  @override
  late final GeneratedColumn<int> serverSequence = GeneratedColumn<int>(
    'server_sequence',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseServerSequenceMeta =
      const VerificationMeta('baseServerSequence');
  @override
  late final GeneratedColumn<int> baseServerSequence = GeneratedColumn<int>(
    'base_server_sequence',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseVersionMeta = const VerificationMeta(
    'baseVersion',
  );
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
    'base_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtLocalMeta = const VerificationMeta(
    'createdAtLocal',
  );
  @override
  late final GeneratedColumn<DateTime> createdAtLocal =
      GeneratedColumn<DateTime>(
        'created_at_local',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtServerMeta = const VerificationMeta(
    'createdAtServer',
  );
  @override
  late final GeneratedColumn<DateTime> createdAtServer =
      GeneratedColumn<DateTime>(
        'created_at_server',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _applicationStatusMeta = const VerificationMeta(
    'applicationStatus',
  );
  @override
  late final GeneratedColumn<String> applicationStatus =
      GeneratedColumn<String>(
        'application_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('applied'),
      );
  static const VerificationMeta _deliveryStatusMeta = const VerificationMeta(
    'deliveryStatus',
  );
  @override
  late final GeneratedColumn<String> deliveryStatus = GeneratedColumn<String>(
    'delivery_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _rejectionReasonMeta = const VerificationMeta(
    'rejectionReason',
  );
  @override
  late final GeneratedColumn<String> rejectionReason = GeneratedColumn<String>(
    'rejection_reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    aggregateType,
    aggregateId,
    eventType,
    deviceId,
    userId,
    localSequence,
    serverSequence,
    baseServerSequence,
    baseVersion,
    createdAtLocal,
    createdAtServer,
    payload,
    applicationStatus,
    deliveryStatus,
    rejectionReason,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('aggregate_type')) {
      context.handle(
        _aggregateTypeMeta,
        aggregateType.isAcceptableOrUnknown(
          data['aggregate_type']!,
          _aggregateTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateTypeMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateIdMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('local_sequence')) {
      context.handle(
        _localSequenceMeta,
        localSequence.isAcceptableOrUnknown(
          data['local_sequence']!,
          _localSequenceMeta,
        ),
      );
    }
    if (data.containsKey('server_sequence')) {
      context.handle(
        _serverSequenceMeta,
        serverSequence.isAcceptableOrUnknown(
          data['server_sequence']!,
          _serverSequenceMeta,
        ),
      );
    }
    if (data.containsKey('base_server_sequence')) {
      context.handle(
        _baseServerSequenceMeta,
        baseServerSequence.isAcceptableOrUnknown(
          data['base_server_sequence']!,
          _baseServerSequenceMeta,
        ),
      );
    }
    if (data.containsKey('base_version')) {
      context.handle(
        _baseVersionMeta,
        baseVersion.isAcceptableOrUnknown(
          data['base_version']!,
          _baseVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at_local')) {
      context.handle(
        _createdAtLocalMeta,
        createdAtLocal.isAcceptableOrUnknown(
          data['created_at_local']!,
          _createdAtLocalMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtLocalMeta);
    }
    if (data.containsKey('created_at_server')) {
      context.handle(
        _createdAtServerMeta,
        createdAtServer.isAcceptableOrUnknown(
          data['created_at_server']!,
          _createdAtServerMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('application_status')) {
      context.handle(
        _applicationStatusMeta,
        applicationStatus.isAcceptableOrUnknown(
          data['application_status']!,
          _applicationStatusMeta,
        ),
      );
    }
    if (data.containsKey('delivery_status')) {
      context.handle(
        _deliveryStatusMeta,
        deliveryStatus.isAcceptableOrUnknown(
          data['delivery_status']!,
          _deliveryStatusMeta,
        ),
      );
    }
    if (data.containsKey('rejection_reason')) {
      context.handle(
        _rejectionReasonMeta,
        rejectionReason.isAcceptableOrUnknown(
          data['rejection_reason']!,
          _rejectionReasonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localSequence};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {eventId},
  ];
  @override
  EventRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventRecord(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      aggregateType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_type'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      localSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_sequence'],
      )!,
      serverSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_sequence'],
      ),
      baseServerSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_server_sequence'],
      ),
      baseVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_version'],
      ),
      createdAtLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_local'],
      )!,
      createdAtServer: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_server'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      applicationStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}application_status'],
      )!,
      deliveryStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}delivery_status'],
      )!,
      rejectionReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejection_reason'],
      ),
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }
}

class EventRecord extends DataClass implements Insertable<EventRecord> {
  /// Unique global ID generated on the device as a UUID
  final String eventId;

  /// The type of aggregate affected (e.g., 'espacio', 'sale', 'product')
  final String aggregateType;

  /// The unique ID of the aggregate affected
  final String aggregateId;

  /// The specific event name/type (e.g., 'espacio_creado', 'producto_creado')
  final String eventType;

  /// The ID of the device that generated the event
  final String deviceId;

  /// The ID of the user that performed the action
  final String userId;

  /// Local sequence order, auto-incremented by the device.
  /// Used as the primary key to ensure strict ordering and auto-increment behavior in SQLite.
  final int localSequence;

  /// Sequence assigned by the server upon successful synchronization
  final int? serverSequence;

  /// Cursor sequence known by the device when generating this event
  final int? baseServerSequence;

  /// Version of the mutable entity known by the device
  final int? baseVersion;

  /// Timestamp of creation on the device
  final DateTime createdAtLocal;

  /// Timestamp of acceptance on the server
  final DateTime? createdAtServer;

  /// JSON payload representing event-specific data (serialized as string)
  final String payload;

  /// Local application status: 'applied' or 'failed'.
  final String applicationStatus;

  /// Remote delivery status: 'not_required', 'pending', 'delivered',
  /// 'rejected' or 'conflict'.
  final String deliveryStatus;

  /// Reason for local rejection or conflict, when available.
  final String? rejectionReason;
  const EventRecord({
    required this.eventId,
    required this.aggregateType,
    required this.aggregateId,
    required this.eventType,
    required this.deviceId,
    required this.userId,
    required this.localSequence,
    this.serverSequence,
    this.baseServerSequence,
    this.baseVersion,
    required this.createdAtLocal,
    this.createdAtServer,
    required this.payload,
    required this.applicationStatus,
    required this.deliveryStatus,
    this.rejectionReason,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    map['aggregate_type'] = Variable<String>(aggregateType);
    map['aggregate_id'] = Variable<String>(aggregateId);
    map['event_type'] = Variable<String>(eventType);
    map['device_id'] = Variable<String>(deviceId);
    map['user_id'] = Variable<String>(userId);
    map['local_sequence'] = Variable<int>(localSequence);
    if (!nullToAbsent || serverSequence != null) {
      map['server_sequence'] = Variable<int>(serverSequence);
    }
    if (!nullToAbsent || baseServerSequence != null) {
      map['base_server_sequence'] = Variable<int>(baseServerSequence);
    }
    if (!nullToAbsent || baseVersion != null) {
      map['base_version'] = Variable<int>(baseVersion);
    }
    map['created_at_local'] = Variable<DateTime>(createdAtLocal);
    if (!nullToAbsent || createdAtServer != null) {
      map['created_at_server'] = Variable<DateTime>(createdAtServer);
    }
    map['payload'] = Variable<String>(payload);
    map['application_status'] = Variable<String>(applicationStatus);
    map['delivery_status'] = Variable<String>(deliveryStatus);
    if (!nullToAbsent || rejectionReason != null) {
      map['rejection_reason'] = Variable<String>(rejectionReason);
    }
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      eventId: Value(eventId),
      aggregateType: Value(aggregateType),
      aggregateId: Value(aggregateId),
      eventType: Value(eventType),
      deviceId: Value(deviceId),
      userId: Value(userId),
      localSequence: Value(localSequence),
      serverSequence: serverSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSequence),
      baseServerSequence: baseServerSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(baseServerSequence),
      baseVersion: baseVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(baseVersion),
      createdAtLocal: Value(createdAtLocal),
      createdAtServer: createdAtServer == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAtServer),
      payload: Value(payload),
      applicationStatus: Value(applicationStatus),
      deliveryStatus: Value(deliveryStatus),
      rejectionReason: rejectionReason == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectionReason),
    );
  }

  factory EventRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventRecord(
      eventId: serializer.fromJson<String>(json['eventId']),
      aggregateType: serializer.fromJson<String>(json['aggregateType']),
      aggregateId: serializer.fromJson<String>(json['aggregateId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      userId: serializer.fromJson<String>(json['userId']),
      localSequence: serializer.fromJson<int>(json['localSequence']),
      serverSequence: serializer.fromJson<int?>(json['serverSequence']),
      baseServerSequence: serializer.fromJson<int?>(json['baseServerSequence']),
      baseVersion: serializer.fromJson<int?>(json['baseVersion']),
      createdAtLocal: serializer.fromJson<DateTime>(json['createdAtLocal']),
      createdAtServer: serializer.fromJson<DateTime?>(json['createdAtServer']),
      payload: serializer.fromJson<String>(json['payload']),
      applicationStatus: serializer.fromJson<String>(json['applicationStatus']),
      deliveryStatus: serializer.fromJson<String>(json['deliveryStatus']),
      rejectionReason: serializer.fromJson<String?>(json['rejectionReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'aggregateType': serializer.toJson<String>(aggregateType),
      'aggregateId': serializer.toJson<String>(aggregateId),
      'eventType': serializer.toJson<String>(eventType),
      'deviceId': serializer.toJson<String>(deviceId),
      'userId': serializer.toJson<String>(userId),
      'localSequence': serializer.toJson<int>(localSequence),
      'serverSequence': serializer.toJson<int?>(serverSequence),
      'baseServerSequence': serializer.toJson<int?>(baseServerSequence),
      'baseVersion': serializer.toJson<int?>(baseVersion),
      'createdAtLocal': serializer.toJson<DateTime>(createdAtLocal),
      'createdAtServer': serializer.toJson<DateTime?>(createdAtServer),
      'payload': serializer.toJson<String>(payload),
      'applicationStatus': serializer.toJson<String>(applicationStatus),
      'deliveryStatus': serializer.toJson<String>(deliveryStatus),
      'rejectionReason': serializer.toJson<String?>(rejectionReason),
    };
  }

  EventRecord copyWith({
    String? eventId,
    String? aggregateType,
    String? aggregateId,
    String? eventType,
    String? deviceId,
    String? userId,
    int? localSequence,
    Value<int?> serverSequence = const Value.absent(),
    Value<int?> baseServerSequence = const Value.absent(),
    Value<int?> baseVersion = const Value.absent(),
    DateTime? createdAtLocal,
    Value<DateTime?> createdAtServer = const Value.absent(),
    String? payload,
    String? applicationStatus,
    String? deliveryStatus,
    Value<String?> rejectionReason = const Value.absent(),
  }) => EventRecord(
    eventId: eventId ?? this.eventId,
    aggregateType: aggregateType ?? this.aggregateType,
    aggregateId: aggregateId ?? this.aggregateId,
    eventType: eventType ?? this.eventType,
    deviceId: deviceId ?? this.deviceId,
    userId: userId ?? this.userId,
    localSequence: localSequence ?? this.localSequence,
    serverSequence: serverSequence.present
        ? serverSequence.value
        : this.serverSequence,
    baseServerSequence: baseServerSequence.present
        ? baseServerSequence.value
        : this.baseServerSequence,
    baseVersion: baseVersion.present ? baseVersion.value : this.baseVersion,
    createdAtLocal: createdAtLocal ?? this.createdAtLocal,
    createdAtServer: createdAtServer.present
        ? createdAtServer.value
        : this.createdAtServer,
    payload: payload ?? this.payload,
    applicationStatus: applicationStatus ?? this.applicationStatus,
    deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    rejectionReason: rejectionReason.present
        ? rejectionReason.value
        : this.rejectionReason,
  );
  EventRecord copyWithCompanion(EventsCompanion data) {
    return EventRecord(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      aggregateType: data.aggregateType.present
          ? data.aggregateType.value
          : this.aggregateType,
      aggregateId: data.aggregateId.present
          ? data.aggregateId.value
          : this.aggregateId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      userId: data.userId.present ? data.userId.value : this.userId,
      localSequence: data.localSequence.present
          ? data.localSequence.value
          : this.localSequence,
      serverSequence: data.serverSequence.present
          ? data.serverSequence.value
          : this.serverSequence,
      baseServerSequence: data.baseServerSequence.present
          ? data.baseServerSequence.value
          : this.baseServerSequence,
      baseVersion: data.baseVersion.present
          ? data.baseVersion.value
          : this.baseVersion,
      createdAtLocal: data.createdAtLocal.present
          ? data.createdAtLocal.value
          : this.createdAtLocal,
      createdAtServer: data.createdAtServer.present
          ? data.createdAtServer.value
          : this.createdAtServer,
      payload: data.payload.present ? data.payload.value : this.payload,
      applicationStatus: data.applicationStatus.present
          ? data.applicationStatus.value
          : this.applicationStatus,
      deliveryStatus: data.deliveryStatus.present
          ? data.deliveryStatus.value
          : this.deliveryStatus,
      rejectionReason: data.rejectionReason.present
          ? data.rejectionReason.value
          : this.rejectionReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventRecord(')
          ..write('eventId: $eventId, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('eventType: $eventType, ')
          ..write('deviceId: $deviceId, ')
          ..write('userId: $userId, ')
          ..write('localSequence: $localSequence, ')
          ..write('serverSequence: $serverSequence, ')
          ..write('baseServerSequence: $baseServerSequence, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('createdAtLocal: $createdAtLocal, ')
          ..write('createdAtServer: $createdAtServer, ')
          ..write('payload: $payload, ')
          ..write('applicationStatus: $applicationStatus, ')
          ..write('deliveryStatus: $deliveryStatus, ')
          ..write('rejectionReason: $rejectionReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    eventId,
    aggregateType,
    aggregateId,
    eventType,
    deviceId,
    userId,
    localSequence,
    serverSequence,
    baseServerSequence,
    baseVersion,
    createdAtLocal,
    createdAtServer,
    payload,
    applicationStatus,
    deliveryStatus,
    rejectionReason,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventRecord &&
          other.eventId == this.eventId &&
          other.aggregateType == this.aggregateType &&
          other.aggregateId == this.aggregateId &&
          other.eventType == this.eventType &&
          other.deviceId == this.deviceId &&
          other.userId == this.userId &&
          other.localSequence == this.localSequence &&
          other.serverSequence == this.serverSequence &&
          other.baseServerSequence == this.baseServerSequence &&
          other.baseVersion == this.baseVersion &&
          other.createdAtLocal == this.createdAtLocal &&
          other.createdAtServer == this.createdAtServer &&
          other.payload == this.payload &&
          other.applicationStatus == this.applicationStatus &&
          other.deliveryStatus == this.deliveryStatus &&
          other.rejectionReason == this.rejectionReason);
}

class EventsCompanion extends UpdateCompanion<EventRecord> {
  final Value<String> eventId;
  final Value<String> aggregateType;
  final Value<String> aggregateId;
  final Value<String> eventType;
  final Value<String> deviceId;
  final Value<String> userId;
  final Value<int> localSequence;
  final Value<int?> serverSequence;
  final Value<int?> baseServerSequence;
  final Value<int?> baseVersion;
  final Value<DateTime> createdAtLocal;
  final Value<DateTime?> createdAtServer;
  final Value<String> payload;
  final Value<String> applicationStatus;
  final Value<String> deliveryStatus;
  final Value<String?> rejectionReason;
  const EventsCompanion({
    this.eventId = const Value.absent(),
    this.aggregateType = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.userId = const Value.absent(),
    this.localSequence = const Value.absent(),
    this.serverSequence = const Value.absent(),
    this.baseServerSequence = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.createdAtLocal = const Value.absent(),
    this.createdAtServer = const Value.absent(),
    this.payload = const Value.absent(),
    this.applicationStatus = const Value.absent(),
    this.deliveryStatus = const Value.absent(),
    this.rejectionReason = const Value.absent(),
  });
  EventsCompanion.insert({
    required String eventId,
    required String aggregateType,
    required String aggregateId,
    required String eventType,
    required String deviceId,
    required String userId,
    this.localSequence = const Value.absent(),
    this.serverSequence = const Value.absent(),
    this.baseServerSequence = const Value.absent(),
    this.baseVersion = const Value.absent(),
    required DateTime createdAtLocal,
    this.createdAtServer = const Value.absent(),
    required String payload,
    this.applicationStatus = const Value.absent(),
    this.deliveryStatus = const Value.absent(),
    this.rejectionReason = const Value.absent(),
  }) : eventId = Value(eventId),
       aggregateType = Value(aggregateType),
       aggregateId = Value(aggregateId),
       eventType = Value(eventType),
       deviceId = Value(deviceId),
       userId = Value(userId),
       createdAtLocal = Value(createdAtLocal),
       payload = Value(payload);
  static Insertable<EventRecord> custom({
    Expression<String>? eventId,
    Expression<String>? aggregateType,
    Expression<String>? aggregateId,
    Expression<String>? eventType,
    Expression<String>? deviceId,
    Expression<String>? userId,
    Expression<int>? localSequence,
    Expression<int>? serverSequence,
    Expression<int>? baseServerSequence,
    Expression<int>? baseVersion,
    Expression<DateTime>? createdAtLocal,
    Expression<DateTime>? createdAtServer,
    Expression<String>? payload,
    Expression<String>? applicationStatus,
    Expression<String>? deliveryStatus,
    Expression<String>? rejectionReason,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (aggregateType != null) 'aggregate_type': aggregateType,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (eventType != null) 'event_type': eventType,
      if (deviceId != null) 'device_id': deviceId,
      if (userId != null) 'user_id': userId,
      if (localSequence != null) 'local_sequence': localSequence,
      if (serverSequence != null) 'server_sequence': serverSequence,
      if (baseServerSequence != null)
        'base_server_sequence': baseServerSequence,
      if (baseVersion != null) 'base_version': baseVersion,
      if (createdAtLocal != null) 'created_at_local': createdAtLocal,
      if (createdAtServer != null) 'created_at_server': createdAtServer,
      if (payload != null) 'payload': payload,
      if (applicationStatus != null) 'application_status': applicationStatus,
      if (deliveryStatus != null) 'delivery_status': deliveryStatus,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
    });
  }

  EventsCompanion copyWith({
    Value<String>? eventId,
    Value<String>? aggregateType,
    Value<String>? aggregateId,
    Value<String>? eventType,
    Value<String>? deviceId,
    Value<String>? userId,
    Value<int>? localSequence,
    Value<int?>? serverSequence,
    Value<int?>? baseServerSequence,
    Value<int?>? baseVersion,
    Value<DateTime>? createdAtLocal,
    Value<DateTime?>? createdAtServer,
    Value<String>? payload,
    Value<String>? applicationStatus,
    Value<String>? deliveryStatus,
    Value<String?>? rejectionReason,
  }) {
    return EventsCompanion(
      eventId: eventId ?? this.eventId,
      aggregateType: aggregateType ?? this.aggregateType,
      aggregateId: aggregateId ?? this.aggregateId,
      eventType: eventType ?? this.eventType,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      localSequence: localSequence ?? this.localSequence,
      serverSequence: serverSequence ?? this.serverSequence,
      baseServerSequence: baseServerSequence ?? this.baseServerSequence,
      baseVersion: baseVersion ?? this.baseVersion,
      createdAtLocal: createdAtLocal ?? this.createdAtLocal,
      createdAtServer: createdAtServer ?? this.createdAtServer,
      payload: payload ?? this.payload,
      applicationStatus: applicationStatus ?? this.applicationStatus,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (aggregateType.present) {
      map['aggregate_type'] = Variable<String>(aggregateType.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (localSequence.present) {
      map['local_sequence'] = Variable<int>(localSequence.value);
    }
    if (serverSequence.present) {
      map['server_sequence'] = Variable<int>(serverSequence.value);
    }
    if (baseServerSequence.present) {
      map['base_server_sequence'] = Variable<int>(baseServerSequence.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (createdAtLocal.present) {
      map['created_at_local'] = Variable<DateTime>(createdAtLocal.value);
    }
    if (createdAtServer.present) {
      map['created_at_server'] = Variable<DateTime>(createdAtServer.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (applicationStatus.present) {
      map['application_status'] = Variable<String>(applicationStatus.value);
    }
    if (deliveryStatus.present) {
      map['delivery_status'] = Variable<String>(deliveryStatus.value);
    }
    if (rejectionReason.present) {
      map['rejection_reason'] = Variable<String>(rejectionReason.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('aggregateType: $aggregateType, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('eventType: $eventType, ')
          ..write('deviceId: $deviceId, ')
          ..write('userId: $userId, ')
          ..write('localSequence: $localSequence, ')
          ..write('serverSequence: $serverSequence, ')
          ..write('baseServerSequence: $baseServerSequence, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('createdAtLocal: $createdAtLocal, ')
          ..write('createdAtServer: $createdAtServer, ')
          ..write('payload: $payload, ')
          ..write('applicationStatus: $applicationStatus, ')
          ..write('deliveryStatus: $deliveryStatus, ')
          ..write('rejectionReason: $rejectionReason')
          ..write(')'))
        .toString();
  }
}

class $EventRefsTable extends EventRefs
    with TableInfo<$EventRefsTable, EventRef> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventRefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventRefIdMeta = const VerificationMeta(
    'eventRefId',
  );
  @override
  late final GeneratedColumn<String> eventRefId = GeneratedColumn<String>(
    'event_ref_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refTypeMeta = const VerificationMeta(
    'refType',
  );
  @override
  late final GeneratedColumn<String> refType = GeneratedColumn<String>(
    'ref_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relationshipMeta = const VerificationMeta(
    'relationship',
  );
  @override
  late final GeneratedColumn<String> relationship = GeneratedColumn<String>(
    'relationship',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverSequenceMeta = const VerificationMeta(
    'serverSequence',
  );
  @override
  late final GeneratedColumn<int> serverSequence = GeneratedColumn<int>(
    'server_sequence',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventRefId,
    eventId,
    refType,
    refId,
    relationship,
    serverSequence,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_refs';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventRef> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_ref_id')) {
      context.handle(
        _eventRefIdMeta,
        eventRefId.isAcceptableOrUnknown(
          data['event_ref_id']!,
          _eventRefIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_eventRefIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('ref_type')) {
      context.handle(
        _refTypeMeta,
        refType.isAcceptableOrUnknown(data['ref_type']!, _refTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_refTypeMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('relationship')) {
      context.handle(
        _relationshipMeta,
        relationship.isAcceptableOrUnknown(
          data['relationship']!,
          _relationshipMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relationshipMeta);
    }
    if (data.containsKey('server_sequence')) {
      context.handle(
        _serverSequenceMeta,
        serverSequence.isAcceptableOrUnknown(
          data['server_sequence']!,
          _serverSequenceMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventRefId};
  @override
  EventRef map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventRef(
      eventRefId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_ref_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      refType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_type'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      )!,
      relationship: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relationship'],
      )!,
      serverSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_sequence'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $EventRefsTable createAlias(String alias) {
    return $EventRefsTable(attachedDatabase, alias);
  }
}

class EventRef extends DataClass implements Insertable<EventRef> {
  /// Unique global ID generated on the device as a UUID
  final String eventRefId;

  /// Reference to the related event's event_id
  final String eventId;

  /// Type of reference (e.g., 'espacio', 'sku', 'user')
  final String refType;

  /// Identifier of the referenced entity or value
  final String refId;

  /// Relationship type (e.g., 'affects', 'uses', 'requires_unique')
  final String relationship;

  /// Sequence assigned by the server upon successful synchronization
  final int? serverSequence;

  /// Source classification: 'server' or 'local_pending'
  final String source;
  const EventRef({
    required this.eventRefId,
    required this.eventId,
    required this.refType,
    required this.refId,
    required this.relationship,
    this.serverSequence,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_ref_id'] = Variable<String>(eventRefId);
    map['event_id'] = Variable<String>(eventId);
    map['ref_type'] = Variable<String>(refType);
    map['ref_id'] = Variable<String>(refId);
    map['relationship'] = Variable<String>(relationship);
    if (!nullToAbsent || serverSequence != null) {
      map['server_sequence'] = Variable<int>(serverSequence);
    }
    map['source'] = Variable<String>(source);
    return map;
  }

  EventRefsCompanion toCompanion(bool nullToAbsent) {
    return EventRefsCompanion(
      eventRefId: Value(eventRefId),
      eventId: Value(eventId),
      refType: Value(refType),
      refId: Value(refId),
      relationship: Value(relationship),
      serverSequence: serverSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSequence),
      source: Value(source),
    );
  }

  factory EventRef.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventRef(
      eventRefId: serializer.fromJson<String>(json['eventRefId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      refType: serializer.fromJson<String>(json['refType']),
      refId: serializer.fromJson<String>(json['refId']),
      relationship: serializer.fromJson<String>(json['relationship']),
      serverSequence: serializer.fromJson<int?>(json['serverSequence']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventRefId': serializer.toJson<String>(eventRefId),
      'eventId': serializer.toJson<String>(eventId),
      'refType': serializer.toJson<String>(refType),
      'refId': serializer.toJson<String>(refId),
      'relationship': serializer.toJson<String>(relationship),
      'serverSequence': serializer.toJson<int?>(serverSequence),
      'source': serializer.toJson<String>(source),
    };
  }

  EventRef copyWith({
    String? eventRefId,
    String? eventId,
    String? refType,
    String? refId,
    String? relationship,
    Value<int?> serverSequence = const Value.absent(),
    String? source,
  }) => EventRef(
    eventRefId: eventRefId ?? this.eventRefId,
    eventId: eventId ?? this.eventId,
    refType: refType ?? this.refType,
    refId: refId ?? this.refId,
    relationship: relationship ?? this.relationship,
    serverSequence: serverSequence.present
        ? serverSequence.value
        : this.serverSequence,
    source: source ?? this.source,
  );
  EventRef copyWithCompanion(EventRefsCompanion data) {
    return EventRef(
      eventRefId: data.eventRefId.present
          ? data.eventRefId.value
          : this.eventRefId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      refType: data.refType.present ? data.refType.value : this.refType,
      refId: data.refId.present ? data.refId.value : this.refId,
      relationship: data.relationship.present
          ? data.relationship.value
          : this.relationship,
      serverSequence: data.serverSequence.present
          ? data.serverSequence.value
          : this.serverSequence,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventRef(')
          ..write('eventRefId: $eventRefId, ')
          ..write('eventId: $eventId, ')
          ..write('refType: $refType, ')
          ..write('refId: $refId, ')
          ..write('relationship: $relationship, ')
          ..write('serverSequence: $serverSequence, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    eventRefId,
    eventId,
    refType,
    refId,
    relationship,
    serverSequence,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventRef &&
          other.eventRefId == this.eventRefId &&
          other.eventId == this.eventId &&
          other.refType == this.refType &&
          other.refId == this.refId &&
          other.relationship == this.relationship &&
          other.serverSequence == this.serverSequence &&
          other.source == this.source);
}

class EventRefsCompanion extends UpdateCompanion<EventRef> {
  final Value<String> eventRefId;
  final Value<String> eventId;
  final Value<String> refType;
  final Value<String> refId;
  final Value<String> relationship;
  final Value<int?> serverSequence;
  final Value<String> source;
  final Value<int> rowid;
  const EventRefsCompanion({
    this.eventRefId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.refType = const Value.absent(),
    this.refId = const Value.absent(),
    this.relationship = const Value.absent(),
    this.serverSequence = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventRefsCompanion.insert({
    required String eventRefId,
    required String eventId,
    required String refType,
    required String refId,
    required String relationship,
    this.serverSequence = const Value.absent(),
    required String source,
    this.rowid = const Value.absent(),
  }) : eventRefId = Value(eventRefId),
       eventId = Value(eventId),
       refType = Value(refType),
       refId = Value(refId),
       relationship = Value(relationship),
       source = Value(source);
  static Insertable<EventRef> custom({
    Expression<String>? eventRefId,
    Expression<String>? eventId,
    Expression<String>? refType,
    Expression<String>? refId,
    Expression<String>? relationship,
    Expression<int>? serverSequence,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventRefId != null) 'event_ref_id': eventRefId,
      if (eventId != null) 'event_id': eventId,
      if (refType != null) 'ref_type': refType,
      if (refId != null) 'ref_id': refId,
      if (relationship != null) 'relationship': relationship,
      if (serverSequence != null) 'server_sequence': serverSequence,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventRefsCompanion copyWith({
    Value<String>? eventRefId,
    Value<String>? eventId,
    Value<String>? refType,
    Value<String>? refId,
    Value<String>? relationship,
    Value<int?>? serverSequence,
    Value<String>? source,
    Value<int>? rowid,
  }) {
    return EventRefsCompanion(
      eventRefId: eventRefId ?? this.eventRefId,
      eventId: eventId ?? this.eventId,
      refType: refType ?? this.refType,
      refId: refId ?? this.refId,
      relationship: relationship ?? this.relationship,
      serverSequence: serverSequence ?? this.serverSequence,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventRefId.present) {
      map['event_ref_id'] = Variable<String>(eventRefId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (refType.present) {
      map['ref_type'] = Variable<String>(refType.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (relationship.present) {
      map['relationship'] = Variable<String>(relationship.value);
    }
    if (serverSequence.present) {
      map['server_sequence'] = Variable<int>(serverSequence.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventRefsCompanion(')
          ..write('eventRefId: $eventRefId, ')
          ..write('eventId: $eventId, ')
          ..write('refType: $refType, ')
          ..write('refId: $refId, ')
          ..write('relationship: $relationship, ')
          ..write('serverSequence: $serverSequence, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCheckpointsTable extends SyncCheckpoints
    with TableInfo<$SyncCheckpointsTable, SyncCheckpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _checkpointIdMeta = const VerificationMeta(
    'checkpointId',
  );
  @override
  late final GeneratedColumn<String> checkpointId = GeneratedColumn<String>(
    'checkpoint_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastFullPullServerSequenceMeta =
      const VerificationMeta('lastFullPullServerSequence');
  @override
  late final GeneratedColumn<int> lastFullPullServerSequence =
      GeneratedColumn<int>(
        'last_full_pull_server_sequence',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _lastPreflightServerSequenceMeta =
      const VerificationMeta('lastPreflightServerSequence');
  @override
  late final GeneratedColumn<int> lastPreflightServerSequence =
      GeneratedColumn<int>(
        'last_preflight_server_sequence',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _lastFullPullAtMeta = const VerificationMeta(
    'lastFullPullAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastFullPullAt =
      GeneratedColumn<DateTime>(
        'last_full_pull_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastPreflightAtMeta = const VerificationMeta(
    'lastPreflightAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPreflightAt =
      GeneratedColumn<DateTime>(
        'last_preflight_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    checkpointId,
    lastFullPullServerSequence,
    lastPreflightServerSequence,
    lastFullPullAt,
    lastPreflightAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCheckpoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('checkpoint_id')) {
      context.handle(
        _checkpointIdMeta,
        checkpointId.isAcceptableOrUnknown(
          data['checkpoint_id']!,
          _checkpointIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_checkpointIdMeta);
    }
    if (data.containsKey('last_full_pull_server_sequence')) {
      context.handle(
        _lastFullPullServerSequenceMeta,
        lastFullPullServerSequence.isAcceptableOrUnknown(
          data['last_full_pull_server_sequence']!,
          _lastFullPullServerSequenceMeta,
        ),
      );
    }
    if (data.containsKey('last_preflight_server_sequence')) {
      context.handle(
        _lastPreflightServerSequenceMeta,
        lastPreflightServerSequence.isAcceptableOrUnknown(
          data['last_preflight_server_sequence']!,
          _lastPreflightServerSequenceMeta,
        ),
      );
    }
    if (data.containsKey('last_full_pull_at')) {
      context.handle(
        _lastFullPullAtMeta,
        lastFullPullAt.isAcceptableOrUnknown(
          data['last_full_pull_at']!,
          _lastFullPullAtMeta,
        ),
      );
    }
    if (data.containsKey('last_preflight_at')) {
      context.handle(
        _lastPreflightAtMeta,
        lastPreflightAt.isAcceptableOrUnknown(
          data['last_preflight_at']!,
          _lastPreflightAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {checkpointId};
  @override
  SyncCheckpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCheckpoint(
      checkpointId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}checkpoint_id'],
      )!,
      lastFullPullServerSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_full_pull_server_sequence'],
      )!,
      lastPreflightServerSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_preflight_server_sequence'],
      )!,
      lastFullPullAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_full_pull_at'],
      ),
      lastPreflightAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_preflight_at'],
      ),
    );
  }

  @override
  $SyncCheckpointsTable createAlias(String alias) {
    return $SyncCheckpointsTable(attachedDatabase, alias);
  }
}

class SyncCheckpoint extends DataClass implements Insertable<SyncCheckpoint> {
  final String checkpointId;
  final int lastFullPullServerSequence;
  final int lastPreflightServerSequence;
  final DateTime? lastFullPullAt;
  final DateTime? lastPreflightAt;
  const SyncCheckpoint({
    required this.checkpointId,
    required this.lastFullPullServerSequence,
    required this.lastPreflightServerSequence,
    this.lastFullPullAt,
    this.lastPreflightAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['checkpoint_id'] = Variable<String>(checkpointId);
    map['last_full_pull_server_sequence'] = Variable<int>(
      lastFullPullServerSequence,
    );
    map['last_preflight_server_sequence'] = Variable<int>(
      lastPreflightServerSequence,
    );
    if (!nullToAbsent || lastFullPullAt != null) {
      map['last_full_pull_at'] = Variable<DateTime>(lastFullPullAt);
    }
    if (!nullToAbsent || lastPreflightAt != null) {
      map['last_preflight_at'] = Variable<DateTime>(lastPreflightAt);
    }
    return map;
  }

  SyncCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return SyncCheckpointsCompanion(
      checkpointId: Value(checkpointId),
      lastFullPullServerSequence: Value(lastFullPullServerSequence),
      lastPreflightServerSequence: Value(lastPreflightServerSequence),
      lastFullPullAt: lastFullPullAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFullPullAt),
      lastPreflightAt: lastPreflightAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPreflightAt),
    );
  }

  factory SyncCheckpoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCheckpoint(
      checkpointId: serializer.fromJson<String>(json['checkpointId']),
      lastFullPullServerSequence: serializer.fromJson<int>(
        json['lastFullPullServerSequence'],
      ),
      lastPreflightServerSequence: serializer.fromJson<int>(
        json['lastPreflightServerSequence'],
      ),
      lastFullPullAt: serializer.fromJson<DateTime?>(json['lastFullPullAt']),
      lastPreflightAt: serializer.fromJson<DateTime?>(json['lastPreflightAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'checkpointId': serializer.toJson<String>(checkpointId),
      'lastFullPullServerSequence': serializer.toJson<int>(
        lastFullPullServerSequence,
      ),
      'lastPreflightServerSequence': serializer.toJson<int>(
        lastPreflightServerSequence,
      ),
      'lastFullPullAt': serializer.toJson<DateTime?>(lastFullPullAt),
      'lastPreflightAt': serializer.toJson<DateTime?>(lastPreflightAt),
    };
  }

  SyncCheckpoint copyWith({
    String? checkpointId,
    int? lastFullPullServerSequence,
    int? lastPreflightServerSequence,
    Value<DateTime?> lastFullPullAt = const Value.absent(),
    Value<DateTime?> lastPreflightAt = const Value.absent(),
  }) => SyncCheckpoint(
    checkpointId: checkpointId ?? this.checkpointId,
    lastFullPullServerSequence:
        lastFullPullServerSequence ?? this.lastFullPullServerSequence,
    lastPreflightServerSequence:
        lastPreflightServerSequence ?? this.lastPreflightServerSequence,
    lastFullPullAt: lastFullPullAt.present
        ? lastFullPullAt.value
        : this.lastFullPullAt,
    lastPreflightAt: lastPreflightAt.present
        ? lastPreflightAt.value
        : this.lastPreflightAt,
  );
  SyncCheckpoint copyWithCompanion(SyncCheckpointsCompanion data) {
    return SyncCheckpoint(
      checkpointId: data.checkpointId.present
          ? data.checkpointId.value
          : this.checkpointId,
      lastFullPullServerSequence: data.lastFullPullServerSequence.present
          ? data.lastFullPullServerSequence.value
          : this.lastFullPullServerSequence,
      lastPreflightServerSequence: data.lastPreflightServerSequence.present
          ? data.lastPreflightServerSequence.value
          : this.lastPreflightServerSequence,
      lastFullPullAt: data.lastFullPullAt.present
          ? data.lastFullPullAt.value
          : this.lastFullPullAt,
      lastPreflightAt: data.lastPreflightAt.present
          ? data.lastPreflightAt.value
          : this.lastPreflightAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCheckpoint(')
          ..write('checkpointId: $checkpointId, ')
          ..write('lastFullPullServerSequence: $lastFullPullServerSequence, ')
          ..write('lastPreflightServerSequence: $lastPreflightServerSequence, ')
          ..write('lastFullPullAt: $lastFullPullAt, ')
          ..write('lastPreflightAt: $lastPreflightAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    checkpointId,
    lastFullPullServerSequence,
    lastPreflightServerSequence,
    lastFullPullAt,
    lastPreflightAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCheckpoint &&
          other.checkpointId == this.checkpointId &&
          other.lastFullPullServerSequence == this.lastFullPullServerSequence &&
          other.lastPreflightServerSequence ==
              this.lastPreflightServerSequence &&
          other.lastFullPullAt == this.lastFullPullAt &&
          other.lastPreflightAt == this.lastPreflightAt);
}

class SyncCheckpointsCompanion extends UpdateCompanion<SyncCheckpoint> {
  final Value<String> checkpointId;
  final Value<int> lastFullPullServerSequence;
  final Value<int> lastPreflightServerSequence;
  final Value<DateTime?> lastFullPullAt;
  final Value<DateTime?> lastPreflightAt;
  final Value<int> rowid;
  const SyncCheckpointsCompanion({
    this.checkpointId = const Value.absent(),
    this.lastFullPullServerSequence = const Value.absent(),
    this.lastPreflightServerSequence = const Value.absent(),
    this.lastFullPullAt = const Value.absent(),
    this.lastPreflightAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCheckpointsCompanion.insert({
    required String checkpointId,
    this.lastFullPullServerSequence = const Value.absent(),
    this.lastPreflightServerSequence = const Value.absent(),
    this.lastFullPullAt = const Value.absent(),
    this.lastPreflightAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : checkpointId = Value(checkpointId);
  static Insertable<SyncCheckpoint> custom({
    Expression<String>? checkpointId,
    Expression<int>? lastFullPullServerSequence,
    Expression<int>? lastPreflightServerSequence,
    Expression<DateTime>? lastFullPullAt,
    Expression<DateTime>? lastPreflightAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (checkpointId != null) 'checkpoint_id': checkpointId,
      if (lastFullPullServerSequence != null)
        'last_full_pull_server_sequence': lastFullPullServerSequence,
      if (lastPreflightServerSequence != null)
        'last_preflight_server_sequence': lastPreflightServerSequence,
      if (lastFullPullAt != null) 'last_full_pull_at': lastFullPullAt,
      if (lastPreflightAt != null) 'last_preflight_at': lastPreflightAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCheckpointsCompanion copyWith({
    Value<String>? checkpointId,
    Value<int>? lastFullPullServerSequence,
    Value<int>? lastPreflightServerSequence,
    Value<DateTime?>? lastFullPullAt,
    Value<DateTime?>? lastPreflightAt,
    Value<int>? rowid,
  }) {
    return SyncCheckpointsCompanion(
      checkpointId: checkpointId ?? this.checkpointId,
      lastFullPullServerSequence:
          lastFullPullServerSequence ?? this.lastFullPullServerSequence,
      lastPreflightServerSequence:
          lastPreflightServerSequence ?? this.lastPreflightServerSequence,
      lastFullPullAt: lastFullPullAt ?? this.lastFullPullAt,
      lastPreflightAt: lastPreflightAt ?? this.lastPreflightAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (checkpointId.present) {
      map['checkpoint_id'] = Variable<String>(checkpointId.value);
    }
    if (lastFullPullServerSequence.present) {
      map['last_full_pull_server_sequence'] = Variable<int>(
        lastFullPullServerSequence.value,
      );
    }
    if (lastPreflightServerSequence.present) {
      map['last_preflight_server_sequence'] = Variable<int>(
        lastPreflightServerSequence.value,
      );
    }
    if (lastFullPullAt.present) {
      map['last_full_pull_at'] = Variable<DateTime>(lastFullPullAt.value);
    }
    if (lastPreflightAt.present) {
      map['last_preflight_at'] = Variable<DateTime>(lastPreflightAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCheckpointsCompanion(')
          ..write('checkpointId: $checkpointId, ')
          ..write('lastFullPullServerSequence: $lastFullPullServerSequence, ')
          ..write('lastPreflightServerSequence: $lastPreflightServerSequence, ')
          ..write('lastFullPullAt: $lastFullPullAt, ')
          ..write('lastPreflightAt: $lastPreflightAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $EspaciosTable espacios = $EspaciosTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $EventRefsTable eventRefs = $EventRefsTable(this);
  late final $SyncCheckpointsTable syncCheckpoints = $SyncCheckpointsTable(
    this,
  );
  late final Index idxEspaciosIdentificacionUnique = Index(
    'idx_espacios_identificacion_unique',
    'CREATE UNIQUE INDEX idx_espacios_identificacion_unique ON espacios (identificacion) WHERE identificacion IS NOT NULL AND identificacion != \'\'',
  );
  late final CategoriaDao categoriaDao = CategoriaDao(this as AppDatabase);
  late final EspacioDao espacioDao = EspacioDao(this as AppDatabase);
  late final EventDao eventDao = EventDao(this as AppDatabase);
  late final EventRefDao eventRefDao = EventRefDao(this as AppDatabase);
  late final SyncCheckpointDao syncCheckpointDao = SyncCheckpointDao(
    this as AppDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    espacios,
    events,
    eventRefs,
    syncCheckpoints,
    idxEspaciosIdentificacionUnique,
  ];
}

typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      required String name,
      Value<String> colorKey,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      Value<String> name,
      Value<String> colorKey,
      Value<int> sortOrder,
      Value<int> rowid,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdEventId => $composableBuilder(
    column: $table.createdEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorKey => $composableBuilder(
    column: $table.colorKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdEventId => $composableBuilder(
    column: $table.createdEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorKey => $composableBuilder(
    column: $table.colorKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get createdEventId => $composableBuilder(
    column: $table.createdEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get colorKey =>
      $composableBuilder(column: $table.colorKey, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (
            CategoryRow,
            BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow>,
          ),
          CategoryRow,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> createdEventId = const Value.absent(),
                Value<String?> lastEventId = const Value.absent(),
                Value<int?> lastServerSequence = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> colorKey = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                name: name,
                colorKey: colorKey,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> createdEventId = const Value.absent(),
                Value<String?> lastEventId = const Value.absent(),
                Value<int?> lastServerSequence = const Value.absent(),
                required String name,
                Value<String> colorKey = const Value.absent(),
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                name: name,
                colorKey: colorKey,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (
        CategoryRow,
        BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow>,
      ),
      CategoryRow,
      PrefetchHooks Function()
    >;
typedef $$EspaciosTableCreateCompanionBuilder =
    EspaciosCompanion Function({
      required String id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      required String nombre,
      Value<String?> identificacion,
      required VisibilidadEspacio visibilidad,
      Value<int> rowid,
    });
typedef $$EspaciosTableUpdateCompanionBuilder =
    EspaciosCompanion Function({
      Value<String> id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      Value<String> nombre,
      Value<String?> identificacion,
      Value<VisibilidadEspacio> visibilidad,
      Value<int> rowid,
    });

class $$EspaciosTableFilterComposer
    extends Composer<_$AppDatabase, $EspaciosTable> {
  $$EspaciosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdEventId => $composableBuilder(
    column: $table.createdEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identificacion => $composableBuilder(
    column: $table.identificacion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<VisibilidadEspacio, VisibilidadEspacio, int>
  get visibilidad => $composableBuilder(
    column: $table.visibilidad,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );
}

class $$EspaciosTableOrderingComposer
    extends Composer<_$AppDatabase, $EspaciosTable> {
  $$EspaciosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdEventId => $composableBuilder(
    column: $table.createdEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nombre => $composableBuilder(
    column: $table.nombre,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identificacion => $composableBuilder(
    column: $table.identificacion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get visibilidad => $composableBuilder(
    column: $table.visibilidad,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EspaciosTableAnnotationComposer
    extends Composer<_$AppDatabase, $EspaciosTable> {
  $$EspaciosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get createdEventId => $composableBuilder(
    column: $table.createdEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastEventId => $composableBuilder(
    column: $table.lastEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastServerSequence => $composableBuilder(
    column: $table.lastServerSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nombre =>
      $composableBuilder(column: $table.nombre, builder: (column) => column);

  GeneratedColumn<String> get identificacion => $composableBuilder(
    column: $table.identificacion,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<VisibilidadEspacio, int> get visibilidad =>
      $composableBuilder(
        column: $table.visibilidad,
        builder: (column) => column,
      );
}

class $$EspaciosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EspaciosTable,
          Espacio,
          $$EspaciosTableFilterComposer,
          $$EspaciosTableOrderingComposer,
          $$EspaciosTableAnnotationComposer,
          $$EspaciosTableCreateCompanionBuilder,
          $$EspaciosTableUpdateCompanionBuilder,
          (Espacio, BaseReferences<_$AppDatabase, $EspaciosTable, Espacio>),
          Espacio,
          PrefetchHooks Function()
        > {
  $$EspaciosTableTableManager(_$AppDatabase db, $EspaciosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EspaciosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EspaciosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EspaciosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> createdEventId = const Value.absent(),
                Value<String?> lastEventId = const Value.absent(),
                Value<int?> lastServerSequence = const Value.absent(),
                Value<String> nombre = const Value.absent(),
                Value<String?> identificacion = const Value.absent(),
                Value<VisibilidadEspacio> visibilidad = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EspaciosCompanion(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                nombre: nombre,
                identificacion: identificacion,
                visibilidad: visibilidad,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> createdEventId = const Value.absent(),
                Value<String?> lastEventId = const Value.absent(),
                Value<int?> lastServerSequence = const Value.absent(),
                required String nombre,
                Value<String?> identificacion = const Value.absent(),
                required VisibilidadEspacio visibilidad,
                Value<int> rowid = const Value.absent(),
              }) => EspaciosCompanion.insert(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                nombre: nombre,
                identificacion: identificacion,
                visibilidad: visibilidad,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EspaciosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EspaciosTable,
      Espacio,
      $$EspaciosTableFilterComposer,
      $$EspaciosTableOrderingComposer,
      $$EspaciosTableAnnotationComposer,
      $$EspaciosTableCreateCompanionBuilder,
      $$EspaciosTableUpdateCompanionBuilder,
      (Espacio, BaseReferences<_$AppDatabase, $EspaciosTable, Espacio>),
      Espacio,
      PrefetchHooks Function()
    >;
typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      required String eventId,
      required String aggregateType,
      required String aggregateId,
      required String eventType,
      required String deviceId,
      required String userId,
      Value<int> localSequence,
      Value<int?> serverSequence,
      Value<int?> baseServerSequence,
      Value<int?> baseVersion,
      required DateTime createdAtLocal,
      Value<DateTime?> createdAtServer,
      required String payload,
      Value<String> applicationStatus,
      Value<String> deliveryStatus,
      Value<String?> rejectionReason,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<String> eventId,
      Value<String> aggregateType,
      Value<String> aggregateId,
      Value<String> eventType,
      Value<String> deviceId,
      Value<String> userId,
      Value<int> localSequence,
      Value<int?> serverSequence,
      Value<int?> baseServerSequence,
      Value<int?> baseVersion,
      Value<DateTime> createdAtLocal,
      Value<DateTime?> createdAtServer,
      Value<String> payload,
      Value<String> applicationStatus,
      Value<String> deliveryStatus,
      Value<String?> rejectionReason,
    });

class $$EventsTableFilterComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseServerSequence => $composableBuilder(
    column: $table.baseServerSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtLocal => $composableBuilder(
    column: $table.createdAtLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtServer => $composableBuilder(
    column: $table.createdAtServer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get applicationStatus => $composableBuilder(
    column: $table.applicationStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rejectionReason => $composableBuilder(
    column: $table.rejectionReason,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseServerSequence => $composableBuilder(
    column: $table.baseServerSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtLocal => $composableBuilder(
    column: $table.createdAtLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtServer => $composableBuilder(
    column: $table.createdAtServer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get applicationStatus => $composableBuilder(
    column: $table.applicationStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rejectionReason => $composableBuilder(
    column: $table.rejectionReason,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get aggregateType => $composableBuilder(
    column: $table.aggregateType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseServerSequence => $composableBuilder(
    column: $table.baseServerSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAtLocal => $composableBuilder(
    column: $table.createdAtLocal,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAtServer => $composableBuilder(
    column: $table.createdAtServer,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get applicationStatus => $composableBuilder(
    column: $table.applicationStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deliveryStatus => $composableBuilder(
    column: $table.deliveryStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rejectionReason => $composableBuilder(
    column: $table.rejectionReason,
    builder: (column) => column,
  );
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventsTable,
          EventRecord,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (
            EventRecord,
            BaseReferences<_$AppDatabase, $EventsTable, EventRecord>,
          ),
          EventRecord,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$AppDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String> aggregateType = const Value.absent(),
                Value<String> aggregateId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> localSequence = const Value.absent(),
                Value<int?> serverSequence = const Value.absent(),
                Value<int?> baseServerSequence = const Value.absent(),
                Value<int?> baseVersion = const Value.absent(),
                Value<DateTime> createdAtLocal = const Value.absent(),
                Value<DateTime?> createdAtServer = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> applicationStatus = const Value.absent(),
                Value<String> deliveryStatus = const Value.absent(),
                Value<String?> rejectionReason = const Value.absent(),
              }) => EventsCompanion(
                eventId: eventId,
                aggregateType: aggregateType,
                aggregateId: aggregateId,
                eventType: eventType,
                deviceId: deviceId,
                userId: userId,
                localSequence: localSequence,
                serverSequence: serverSequence,
                baseServerSequence: baseServerSequence,
                baseVersion: baseVersion,
                createdAtLocal: createdAtLocal,
                createdAtServer: createdAtServer,
                payload: payload,
                applicationStatus: applicationStatus,
                deliveryStatus: deliveryStatus,
                rejectionReason: rejectionReason,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                required String aggregateType,
                required String aggregateId,
                required String eventType,
                required String deviceId,
                required String userId,
                Value<int> localSequence = const Value.absent(),
                Value<int?> serverSequence = const Value.absent(),
                Value<int?> baseServerSequence = const Value.absent(),
                Value<int?> baseVersion = const Value.absent(),
                required DateTime createdAtLocal,
                Value<DateTime?> createdAtServer = const Value.absent(),
                required String payload,
                Value<String> applicationStatus = const Value.absent(),
                Value<String> deliveryStatus = const Value.absent(),
                Value<String?> rejectionReason = const Value.absent(),
              }) => EventsCompanion.insert(
                eventId: eventId,
                aggregateType: aggregateType,
                aggregateId: aggregateId,
                eventType: eventType,
                deviceId: deviceId,
                userId: userId,
                localSequence: localSequence,
                serverSequence: serverSequence,
                baseServerSequence: baseServerSequence,
                baseVersion: baseVersion,
                createdAtLocal: createdAtLocal,
                createdAtServer: createdAtServer,
                payload: payload,
                applicationStatus: applicationStatus,
                deliveryStatus: deliveryStatus,
                rejectionReason: rejectionReason,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventsTable,
      EventRecord,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (EventRecord, BaseReferences<_$AppDatabase, $EventsTable, EventRecord>),
      EventRecord,
      PrefetchHooks Function()
    >;
typedef $$EventRefsTableCreateCompanionBuilder =
    EventRefsCompanion Function({
      required String eventRefId,
      required String eventId,
      required String refType,
      required String refId,
      required String relationship,
      Value<int?> serverSequence,
      required String source,
      Value<int> rowid,
    });
typedef $$EventRefsTableUpdateCompanionBuilder =
    EventRefsCompanion Function({
      Value<String> eventRefId,
      Value<String> eventId,
      Value<String> refType,
      Value<String> refId,
      Value<String> relationship,
      Value<int?> serverSequence,
      Value<String> source,
      Value<int> rowid,
    });

class $$EventRefsTableFilterComposer
    extends Composer<_$AppDatabase, $EventRefsTable> {
  $$EventRefsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventRefId => $composableBuilder(
    column: $table.eventRefId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refType => $composableBuilder(
    column: $table.refType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventRefsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventRefsTable> {
  $$EventRefsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventRefId => $composableBuilder(
    column: $table.eventRefId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refType => $composableBuilder(
    column: $table.refType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventRefsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventRefsTable> {
  $$EventRefsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventRefId => $composableBuilder(
    column: $table.eventRefId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get refType =>
      $composableBuilder(column: $table.refType, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get relationship => $composableBuilder(
    column: $table.relationship,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$EventRefsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventRefsTable,
          EventRef,
          $$EventRefsTableFilterComposer,
          $$EventRefsTableOrderingComposer,
          $$EventRefsTableAnnotationComposer,
          $$EventRefsTableCreateCompanionBuilder,
          $$EventRefsTableUpdateCompanionBuilder,
          (EventRef, BaseReferences<_$AppDatabase, $EventRefsTable, EventRef>),
          EventRef,
          PrefetchHooks Function()
        > {
  $$EventRefsTableTableManager(_$AppDatabase db, $EventRefsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventRefsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventRefsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventRefsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventRefId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> refType = const Value.absent(),
                Value<String> refId = const Value.absent(),
                Value<String> relationship = const Value.absent(),
                Value<int?> serverSequence = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventRefsCompanion(
                eventRefId: eventRefId,
                eventId: eventId,
                refType: refType,
                refId: refId,
                relationship: relationship,
                serverSequence: serverSequence,
                source: source,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventRefId,
                required String eventId,
                required String refType,
                required String refId,
                required String relationship,
                Value<int?> serverSequence = const Value.absent(),
                required String source,
                Value<int> rowid = const Value.absent(),
              }) => EventRefsCompanion.insert(
                eventRefId: eventRefId,
                eventId: eventId,
                refType: refType,
                refId: refId,
                relationship: relationship,
                serverSequence: serverSequence,
                source: source,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventRefsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventRefsTable,
      EventRef,
      $$EventRefsTableFilterComposer,
      $$EventRefsTableOrderingComposer,
      $$EventRefsTableAnnotationComposer,
      $$EventRefsTableCreateCompanionBuilder,
      $$EventRefsTableUpdateCompanionBuilder,
      (EventRef, BaseReferences<_$AppDatabase, $EventRefsTable, EventRef>),
      EventRef,
      PrefetchHooks Function()
    >;
typedef $$SyncCheckpointsTableCreateCompanionBuilder =
    SyncCheckpointsCompanion Function({
      required String checkpointId,
      Value<int> lastFullPullServerSequence,
      Value<int> lastPreflightServerSequence,
      Value<DateTime?> lastFullPullAt,
      Value<DateTime?> lastPreflightAt,
      Value<int> rowid,
    });
typedef $$SyncCheckpointsTableUpdateCompanionBuilder =
    SyncCheckpointsCompanion Function({
      Value<String> checkpointId,
      Value<int> lastFullPullServerSequence,
      Value<int> lastPreflightServerSequence,
      Value<DateTime?> lastFullPullAt,
      Value<DateTime?> lastPreflightAt,
      Value<int> rowid,
    });

class $$SyncCheckpointsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get checkpointId => $composableBuilder(
    column: $table.checkpointId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastFullPullServerSequence => $composableBuilder(
    column: $table.lastFullPullServerSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPreflightServerSequence => $composableBuilder(
    column: $table.lastPreflightServerSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastFullPullAt => $composableBuilder(
    column: $table.lastFullPullAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPreflightAt => $composableBuilder(
    column: $table.lastPreflightAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCheckpointsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get checkpointId => $composableBuilder(
    column: $table.checkpointId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastFullPullServerSequence => $composableBuilder(
    column: $table.lastFullPullServerSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPreflightServerSequence => $composableBuilder(
    column: $table.lastPreflightServerSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastFullPullAt => $composableBuilder(
    column: $table.lastFullPullAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPreflightAt => $composableBuilder(
    column: $table.lastPreflightAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCheckpointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCheckpointsTable> {
  $$SyncCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get checkpointId => $composableBuilder(
    column: $table.checkpointId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastFullPullServerSequence => $composableBuilder(
    column: $table.lastFullPullServerSequence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastPreflightServerSequence => $composableBuilder(
    column: $table.lastPreflightServerSequence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastFullPullAt => $composableBuilder(
    column: $table.lastFullPullAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastPreflightAt => $composableBuilder(
    column: $table.lastPreflightAt,
    builder: (column) => column,
  );
}

class $$SyncCheckpointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCheckpointsTable,
          SyncCheckpoint,
          $$SyncCheckpointsTableFilterComposer,
          $$SyncCheckpointsTableOrderingComposer,
          $$SyncCheckpointsTableAnnotationComposer,
          $$SyncCheckpointsTableCreateCompanionBuilder,
          $$SyncCheckpointsTableUpdateCompanionBuilder,
          (
            SyncCheckpoint,
            BaseReferences<
              _$AppDatabase,
              $SyncCheckpointsTable,
              SyncCheckpoint
            >,
          ),
          SyncCheckpoint,
          PrefetchHooks Function()
        > {
  $$SyncCheckpointsTableTableManager(
    _$AppDatabase db,
    $SyncCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCheckpointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCheckpointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> checkpointId = const Value.absent(),
                Value<int> lastFullPullServerSequence = const Value.absent(),
                Value<int> lastPreflightServerSequence = const Value.absent(),
                Value<DateTime?> lastFullPullAt = const Value.absent(),
                Value<DateTime?> lastPreflightAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCheckpointsCompanion(
                checkpointId: checkpointId,
                lastFullPullServerSequence: lastFullPullServerSequence,
                lastPreflightServerSequence: lastPreflightServerSequence,
                lastFullPullAt: lastFullPullAt,
                lastPreflightAt: lastPreflightAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String checkpointId,
                Value<int> lastFullPullServerSequence = const Value.absent(),
                Value<int> lastPreflightServerSequence = const Value.absent(),
                Value<DateTime?> lastFullPullAt = const Value.absent(),
                Value<DateTime?> lastPreflightAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCheckpointsCompanion.insert(
                checkpointId: checkpointId,
                lastFullPullServerSequence: lastFullPullServerSequence,
                lastPreflightServerSequence: lastPreflightServerSequence,
                lastFullPullAt: lastFullPullAt,
                lastPreflightAt: lastPreflightAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCheckpointsTable,
      SyncCheckpoint,
      $$SyncCheckpointsTableFilterComposer,
      $$SyncCheckpointsTableOrderingComposer,
      $$SyncCheckpointsTableAnnotationComposer,
      $$SyncCheckpointsTableCreateCompanionBuilder,
      $$SyncCheckpointsTableUpdateCompanionBuilder,
      (
        SyncCheckpoint,
        BaseReferences<_$AppDatabase, $SyncCheckpointsTable, SyncCheckpoint>,
      ),
      SyncCheckpoint,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$EspaciosTableTableManager get espacios =>
      $$EspaciosTableTableManager(_db, _db.espacios);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$EventRefsTableTableManager get eventRefs =>
      $$EventRefsTableTableManager(_db, _db.eventRefs);
  $$SyncCheckpointsTableTableManager get syncCheckpoints =>
      $$SyncCheckpointsTableTableManager(_db, _db.syncCheckpoints);
}

mixin _$CategoriaDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  CategoriaDaoManager get managers => CategoriaDaoManager(this);
}

class CategoriaDaoManager {
  final _$CategoriaDaoMixin _db;
  CategoriaDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
}

mixin _$EspacioDaoMixin on DatabaseAccessor<AppDatabase> {
  $EspaciosTable get espacios => attachedDatabase.espacios;
  EspacioDaoManager get managers => EspacioDaoManager(this);
}

class EspacioDaoManager {
  final _$EspacioDaoMixin _db;
  EspacioDaoManager(this._db);
  $$EspaciosTableTableManager get espacios =>
      $$EspaciosTableTableManager(_db.attachedDatabase, _db.espacios);
}

mixin _$EventDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventsTable get events => attachedDatabase.events;
  EventDaoManager get managers => EventDaoManager(this);
}

class EventDaoManager {
  final _$EventDaoMixin _db;
  EventDaoManager(this._db);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db.attachedDatabase, _db.events);
}

mixin _$EventRefDaoMixin on DatabaseAccessor<AppDatabase> {
  $EventRefsTable get eventRefs => attachedDatabase.eventRefs;
  EventRefDaoManager get managers => EventRefDaoManager(this);
}

class EventRefDaoManager {
  final _$EventRefDaoMixin _db;
  EventRefDaoManager(this._db);
  $$EventRefsTableTableManager get eventRefs =>
      $$EventRefsTableTableManager(_db.attachedDatabase, _db.eventRefs);
}

mixin _$SyncCheckpointDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncCheckpointsTable get syncCheckpoints => attachedDatabase.syncCheckpoints;
  SyncCheckpointDaoManager get managers => SyncCheckpointDaoManager(this);
}

class SyncCheckpointDaoManager {
  final _$SyncCheckpointDaoMixin _db;
  SyncCheckpointDaoManager(this._db);
  $$SyncCheckpointsTableTableManager get syncCheckpoints =>
      $$SyncCheckpointsTableTableManager(
        _db.attachedDatabase,
        _db.syncCheckpoints,
      );
}
