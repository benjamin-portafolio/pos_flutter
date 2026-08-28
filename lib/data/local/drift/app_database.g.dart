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

class $UnitsTable extends Units with TableInfo<$UnitsTable, UnitRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UnitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _unitIdMeta = const VerificationMeta('unitId');
  @override
  late final GeneratedColumn<String> unitId = GeneratedColumn<String>(
    'unit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 16,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dimensionMeta = const VerificationMeta(
    'dimension',
  );
  @override
  late final GeneratedColumn<String> dimension = GeneratedColumn<String>(
    'dimension',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (dimension IN (\'count\', \'mass\', \'volume\'))',
  );
  static const VerificationMeta _atomicFactorMeta = const VerificationMeta(
    'atomicFactor',
  );
  @override
  late final GeneratedColumn<int> atomicFactor = GeneratedColumn<int>(
    'atomic_factor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (atomic_factor > 0)',
  );
  static const VerificationMeta _maxFractionDigitsMeta = const VerificationMeta(
    'maxFractionDigits',
  );
  @override
  late final GeneratedColumn<int> maxFractionDigits = GeneratedColumn<int>(
    'max_fraction_digits',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL CHECK (max_fraction_digits >= 0 AND max_fraction_digits <= 9)',
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
  @override
  List<GeneratedColumn> get $columns => [
    unitId,
    code,
    name,
    symbol,
    dimension,
    atomicFactor,
    maxFractionDigits,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'units';
  @override
  VerificationContext validateIntegrity(
    Insertable<UnitRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('unit_id')) {
      context.handle(
        _unitIdMeta,
        unitId.isAcceptableOrUnknown(data['unit_id']!, _unitIdMeta),
      );
    } else if (isInserting) {
      context.missing(_unitIdMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('dimension')) {
      context.handle(
        _dimensionMeta,
        dimension.isAcceptableOrUnknown(data['dimension']!, _dimensionMeta),
      );
    } else if (isInserting) {
      context.missing(_dimensionMeta);
    }
    if (data.containsKey('atomic_factor')) {
      context.handle(
        _atomicFactorMeta,
        atomicFactor.isAcceptableOrUnknown(
          data['atomic_factor']!,
          _atomicFactorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_atomicFactorMeta);
    }
    if (data.containsKey('max_fraction_digits')) {
      context.handle(
        _maxFractionDigitsMeta,
        maxFractionDigits.isAcceptableOrUnknown(
          data['max_fraction_digits']!,
          _maxFractionDigitsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_maxFractionDigitsMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {unitId};
  @override
  UnitRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UnitRow(
      unitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit_id'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      dimension: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dimension'],
      )!,
      atomicFactor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}atomic_factor'],
      )!,
      maxFractionDigits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}max_fraction_digits'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $UnitsTable createAlias(String alias) {
    return $UnitsTable(attachedDatabase, alias);
  }
}

class UnitRow extends DataClass implements Insertable<UnitRow> {
  /// UUID estable e idéntico en cada dispositivo y en el servidor.
  final String unitId;

  /// Código estable usado por migraciones y reglas de interoperabilidad.
  final String code;

  /// Nombre localizado que se muestra al usuario.
  final String name;

  /// Abreviatura visible junto a las cantidades.
  final String symbol;

  /// Dimensión física: `count`, `mass` o `volume`.
  final String dimension;

  /// Número de átomos de la dimensión representados por una unidad.
  final int atomicFactor;

  /// Máximo de decimales aceptados al capturar cantidades en esta unidad.
  final int maxFractionDigits;

  /// Determina si la unidad puede seleccionarse en nuevas operaciones.
  final bool active;
  const UnitRow({
    required this.unitId,
    required this.code,
    required this.name,
    required this.symbol,
    required this.dimension,
    required this.atomicFactor,
    required this.maxFractionDigits,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['unit_id'] = Variable<String>(unitId);
    map['code'] = Variable<String>(code);
    map['name'] = Variable<String>(name);
    map['symbol'] = Variable<String>(symbol);
    map['dimension'] = Variable<String>(dimension);
    map['atomic_factor'] = Variable<int>(atomicFactor);
    map['max_fraction_digits'] = Variable<int>(maxFractionDigits);
    map['active'] = Variable<bool>(active);
    return map;
  }

  UnitsCompanion toCompanion(bool nullToAbsent) {
    return UnitsCompanion(
      unitId: Value(unitId),
      code: Value(code),
      name: Value(name),
      symbol: Value(symbol),
      dimension: Value(dimension),
      atomicFactor: Value(atomicFactor),
      maxFractionDigits: Value(maxFractionDigits),
      active: Value(active),
    );
  }

  factory UnitRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UnitRow(
      unitId: serializer.fromJson<String>(json['unitId']),
      code: serializer.fromJson<String>(json['code']),
      name: serializer.fromJson<String>(json['name']),
      symbol: serializer.fromJson<String>(json['symbol']),
      dimension: serializer.fromJson<String>(json['dimension']),
      atomicFactor: serializer.fromJson<int>(json['atomicFactor']),
      maxFractionDigits: serializer.fromJson<int>(json['maxFractionDigits']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'unitId': serializer.toJson<String>(unitId),
      'code': serializer.toJson<String>(code),
      'name': serializer.toJson<String>(name),
      'symbol': serializer.toJson<String>(symbol),
      'dimension': serializer.toJson<String>(dimension),
      'atomicFactor': serializer.toJson<int>(atomicFactor),
      'maxFractionDigits': serializer.toJson<int>(maxFractionDigits),
      'active': serializer.toJson<bool>(active),
    };
  }

  UnitRow copyWith({
    String? unitId,
    String? code,
    String? name,
    String? symbol,
    String? dimension,
    int? atomicFactor,
    int? maxFractionDigits,
    bool? active,
  }) => UnitRow(
    unitId: unitId ?? this.unitId,
    code: code ?? this.code,
    name: name ?? this.name,
    symbol: symbol ?? this.symbol,
    dimension: dimension ?? this.dimension,
    atomicFactor: atomicFactor ?? this.atomicFactor,
    maxFractionDigits: maxFractionDigits ?? this.maxFractionDigits,
    active: active ?? this.active,
  );
  UnitRow copyWithCompanion(UnitsCompanion data) {
    return UnitRow(
      unitId: data.unitId.present ? data.unitId.value : this.unitId,
      code: data.code.present ? data.code.value : this.code,
      name: data.name.present ? data.name.value : this.name,
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      dimension: data.dimension.present ? data.dimension.value : this.dimension,
      atomicFactor: data.atomicFactor.present
          ? data.atomicFactor.value
          : this.atomicFactor,
      maxFractionDigits: data.maxFractionDigits.present
          ? data.maxFractionDigits.value
          : this.maxFractionDigits,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UnitRow(')
          ..write('unitId: $unitId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('symbol: $symbol, ')
          ..write('dimension: $dimension, ')
          ..write('atomicFactor: $atomicFactor, ')
          ..write('maxFractionDigits: $maxFractionDigits, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    unitId,
    code,
    name,
    symbol,
    dimension,
    atomicFactor,
    maxFractionDigits,
    active,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UnitRow &&
          other.unitId == this.unitId &&
          other.code == this.code &&
          other.name == this.name &&
          other.symbol == this.symbol &&
          other.dimension == this.dimension &&
          other.atomicFactor == this.atomicFactor &&
          other.maxFractionDigits == this.maxFractionDigits &&
          other.active == this.active);
}

class UnitsCompanion extends UpdateCompanion<UnitRow> {
  final Value<String> unitId;
  final Value<String> code;
  final Value<String> name;
  final Value<String> symbol;
  final Value<String> dimension;
  final Value<int> atomicFactor;
  final Value<int> maxFractionDigits;
  final Value<bool> active;
  final Value<int> rowid;
  const UnitsCompanion({
    this.unitId = const Value.absent(),
    this.code = const Value.absent(),
    this.name = const Value.absent(),
    this.symbol = const Value.absent(),
    this.dimension = const Value.absent(),
    this.atomicFactor = const Value.absent(),
    this.maxFractionDigits = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UnitsCompanion.insert({
    required String unitId,
    required String code,
    required String name,
    required String symbol,
    required String dimension,
    required int atomicFactor,
    required int maxFractionDigits,
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : unitId = Value(unitId),
       code = Value(code),
       name = Value(name),
       symbol = Value(symbol),
       dimension = Value(dimension),
       atomicFactor = Value(atomicFactor),
       maxFractionDigits = Value(maxFractionDigits);
  static Insertable<UnitRow> custom({
    Expression<String>? unitId,
    Expression<String>? code,
    Expression<String>? name,
    Expression<String>? symbol,
    Expression<String>? dimension,
    Expression<int>? atomicFactor,
    Expression<int>? maxFractionDigits,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (unitId != null) 'unit_id': unitId,
      if (code != null) 'code': code,
      if (name != null) 'name': name,
      if (symbol != null) 'symbol': symbol,
      if (dimension != null) 'dimension': dimension,
      if (atomicFactor != null) 'atomic_factor': atomicFactor,
      if (maxFractionDigits != null) 'max_fraction_digits': maxFractionDigits,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UnitsCompanion copyWith({
    Value<String>? unitId,
    Value<String>? code,
    Value<String>? name,
    Value<String>? symbol,
    Value<String>? dimension,
    Value<int>? atomicFactor,
    Value<int>? maxFractionDigits,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return UnitsCompanion(
      unitId: unitId ?? this.unitId,
      code: code ?? this.code,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      dimension: dimension ?? this.dimension,
      atomicFactor: atomicFactor ?? this.atomicFactor,
      maxFractionDigits: maxFractionDigits ?? this.maxFractionDigits,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (unitId.present) {
      map['unit_id'] = Variable<String>(unitId.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (dimension.present) {
      map['dimension'] = Variable<String>(dimension.value);
    }
    if (atomicFactor.present) {
      map['atomic_factor'] = Variable<int>(atomicFactor.value);
    }
    if (maxFractionDigits.present) {
      map['max_fraction_digits'] = Variable<int>(maxFractionDigits.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UnitsCompanion(')
          ..write('unitId: $unitId, ')
          ..write('code: $code, ')
          ..write('name: $name, ')
          ..write('symbol: $symbol, ')
          ..write('dimension: $dimension, ')
          ..write('atomicFactor: $atomicFactor, ')
          ..write('maxFractionDigits: $maxFractionDigits, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products
    with TableInfo<$ProductsTable, ProductRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
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
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 160,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _saleModeMeta = const VerificationMeta(
    'saleMode',
  );
  @override
  late final GeneratedColumn<String> saleMode = GeneratedColumn<String>(
    'sale_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    $customConstraints:
        'NOT NULL DEFAULT \'unit\' CHECK (sale_mode IN (\'unit\', \'measured\'))',
    defaultValue: const CustomExpression('\'unit\''),
  );
  static const VerificationMeta _saleUnitIdMeta = const VerificationMeta(
    'saleUnitId',
  );
  @override
  late final GeneratedColumn<String> saleUnitId = GeneratedColumn<String>(
    'sale_unit_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES units (unit_id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _priceReferenceQuantityAtomicMeta =
      const VerificationMeta('priceReferenceQuantityAtomic');
  @override
  late final GeneratedColumn<int> priceReferenceQuantityAtomic =
      GeneratedColumn<int>(
        'price_reference_quantity_atomic',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
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
    categoryId,
    saleMode,
    saleUnitId,
    priceReferenceQuantityAtomic,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductRow> instance, {
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
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('sale_mode')) {
      context.handle(
        _saleModeMeta,
        saleMode.isAcceptableOrUnknown(data['sale_mode']!, _saleModeMeta),
      );
    }
    if (data.containsKey('sale_unit_id')) {
      context.handle(
        _saleUnitIdMeta,
        saleUnitId.isAcceptableOrUnknown(
          data['sale_unit_id']!,
          _saleUnitIdMeta,
        ),
      );
    }
    if (data.containsKey('price_reference_quantity_atomic')) {
      context.handle(
        _priceReferenceQuantityAtomicMeta,
        priceReferenceQuantityAtomic.isAcceptableOrUnknown(
          data['price_reference_quantity_atomic']!,
          _priceReferenceQuantityAtomicMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductRow(
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
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      saleMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_mode'],
      )!,
      saleUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_unit_id'],
      ),
      priceReferenceQuantityAtomic: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_reference_quantity_atomic'],
      ),
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class ProductRow extends DataClass implements Insertable<ProductRow> {
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

  /// Nombre comercial visible del articulo.
  final String name;

  /// Categoria opcional usada para organizar el articulo; `null` significa
  /// que el usuario eligio `Sin categoria`.
  final String? categoryId;

  /// Forma de captura de la cantidad vendida: unidad completa o medida.
  final String saleMode;

  /// Unidad activa de masa o volumen usada para una venta medida.
  final String? saleUnitId;

  /// Átomos de la unidad seleccionada a los que corresponde el precio.
  final int? priceReferenceQuantityAtomic;
  const ProductRow({
    required this.id,
    required this.active,
    required this.version,
    this.createdEventId,
    this.lastEventId,
    this.lastServerSequence,
    required this.name,
    this.categoryId,
    required this.saleMode,
    this.saleUnitId,
    this.priceReferenceQuantityAtomic,
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
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['sale_mode'] = Variable<String>(saleMode);
    if (!nullToAbsent || saleUnitId != null) {
      map['sale_unit_id'] = Variable<String>(saleUnitId);
    }
    if (!nullToAbsent || priceReferenceQuantityAtomic != null) {
      map['price_reference_quantity_atomic'] = Variable<int>(
        priceReferenceQuantityAtomic,
      );
    }
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
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
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      saleMode: Value(saleMode),
      saleUnitId: saleUnitId == null && nullToAbsent
          ? const Value.absent()
          : Value(saleUnitId),
      priceReferenceQuantityAtomic:
          priceReferenceQuantityAtomic == null && nullToAbsent
          ? const Value.absent()
          : Value(priceReferenceQuantityAtomic),
    );
  }

  factory ProductRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductRow(
      id: serializer.fromJson<String>(json['id']),
      active: serializer.fromJson<bool>(json['active']),
      version: serializer.fromJson<int>(json['version']),
      createdEventId: serializer.fromJson<String?>(json['createdEventId']),
      lastEventId: serializer.fromJson<String?>(json['lastEventId']),
      lastServerSequence: serializer.fromJson<int?>(json['lastServerSequence']),
      name: serializer.fromJson<String>(json['name']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      saleMode: serializer.fromJson<String>(json['saleMode']),
      saleUnitId: serializer.fromJson<String?>(json['saleUnitId']),
      priceReferenceQuantityAtomic: serializer.fromJson<int?>(
        json['priceReferenceQuantityAtomic'],
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
      'name': serializer.toJson<String>(name),
      'categoryId': serializer.toJson<String?>(categoryId),
      'saleMode': serializer.toJson<String>(saleMode),
      'saleUnitId': serializer.toJson<String?>(saleUnitId),
      'priceReferenceQuantityAtomic': serializer.toJson<int?>(
        priceReferenceQuantityAtomic,
      ),
    };
  }

  ProductRow copyWith({
    String? id,
    bool? active,
    int? version,
    Value<String?> createdEventId = const Value.absent(),
    Value<String?> lastEventId = const Value.absent(),
    Value<int?> lastServerSequence = const Value.absent(),
    String? name,
    Value<String?> categoryId = const Value.absent(),
    String? saleMode,
    Value<String?> saleUnitId = const Value.absent(),
    Value<int?> priceReferenceQuantityAtomic = const Value.absent(),
  }) => ProductRow(
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
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    saleMode: saleMode ?? this.saleMode,
    saleUnitId: saleUnitId.present ? saleUnitId.value : this.saleUnitId,
    priceReferenceQuantityAtomic: priceReferenceQuantityAtomic.present
        ? priceReferenceQuantityAtomic.value
        : this.priceReferenceQuantityAtomic,
  );
  ProductRow copyWithCompanion(ProductsCompanion data) {
    return ProductRow(
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
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      saleMode: data.saleMode.present ? data.saleMode.value : this.saleMode,
      saleUnitId: data.saleUnitId.present
          ? data.saleUnitId.value
          : this.saleUnitId,
      priceReferenceQuantityAtomic: data.priceReferenceQuantityAtomic.present
          ? data.priceReferenceQuantityAtomic.value
          : this.priceReferenceQuantityAtomic,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductRow(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('saleMode: $saleMode, ')
          ..write('saleUnitId: $saleUnitId, ')
          ..write('priceReferenceQuantityAtomic: $priceReferenceQuantityAtomic')
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
    categoryId,
    saleMode,
    saleUnitId,
    priceReferenceQuantityAtomic,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductRow &&
          other.id == this.id &&
          other.active == this.active &&
          other.version == this.version &&
          other.createdEventId == this.createdEventId &&
          other.lastEventId == this.lastEventId &&
          other.lastServerSequence == this.lastServerSequence &&
          other.name == this.name &&
          other.categoryId == this.categoryId &&
          other.saleMode == this.saleMode &&
          other.saleUnitId == this.saleUnitId &&
          other.priceReferenceQuantityAtomic ==
              this.priceReferenceQuantityAtomic);
}

class ProductsCompanion extends UpdateCompanion<ProductRow> {
  final Value<String> id;
  final Value<bool> active;
  final Value<int> version;
  final Value<String?> createdEventId;
  final Value<String?> lastEventId;
  final Value<int?> lastServerSequence;
  final Value<String> name;
  final Value<String?> categoryId;
  final Value<String> saleMode;
  final Value<String?> saleUnitId;
  final Value<int?> priceReferenceQuantityAtomic;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.saleMode = const Value.absent(),
    this.saleUnitId = const Value.absent(),
    this.priceReferenceQuantityAtomic = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    required String name,
    this.categoryId = const Value.absent(),
    this.saleMode = const Value.absent(),
    this.saleUnitId = const Value.absent(),
    this.priceReferenceQuantityAtomic = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<ProductRow> custom({
    Expression<String>? id,
    Expression<bool>? active,
    Expression<int>? version,
    Expression<String>? createdEventId,
    Expression<String>? lastEventId,
    Expression<int>? lastServerSequence,
    Expression<String>? name,
    Expression<String>? categoryId,
    Expression<String>? saleMode,
    Expression<String>? saleUnitId,
    Expression<int>? priceReferenceQuantityAtomic,
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
      if (categoryId != null) 'category_id': categoryId,
      if (saleMode != null) 'sale_mode': saleMode,
      if (saleUnitId != null) 'sale_unit_id': saleUnitId,
      if (priceReferenceQuantityAtomic != null)
        'price_reference_quantity_atomic': priceReferenceQuantityAtomic,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith({
    Value<String>? id,
    Value<bool>? active,
    Value<int>? version,
    Value<String?>? createdEventId,
    Value<String?>? lastEventId,
    Value<int?>? lastServerSequence,
    Value<String>? name,
    Value<String?>? categoryId,
    Value<String>? saleMode,
    Value<String?>? saleUnitId,
    Value<int?>? priceReferenceQuantityAtomic,
    Value<int>? rowid,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      active: active ?? this.active,
      version: version ?? this.version,
      createdEventId: createdEventId ?? this.createdEventId,
      lastEventId: lastEventId ?? this.lastEventId,
      lastServerSequence: lastServerSequence ?? this.lastServerSequence,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      saleMode: saleMode ?? this.saleMode,
      saleUnitId: saleUnitId ?? this.saleUnitId,
      priceReferenceQuantityAtomic:
          priceReferenceQuantityAtomic ?? this.priceReferenceQuantityAtomic,
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
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (saleMode.present) {
      map['sale_mode'] = Variable<String>(saleMode.value);
    }
    if (saleUnitId.present) {
      map['sale_unit_id'] = Variable<String>(saleUnitId.value);
    }
    if (priceReferenceQuantityAtomic.present) {
      map['price_reference_quantity_atomic'] = Variable<int>(
        priceReferenceQuantityAtomic.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('saleMode: $saleMode, ')
          ..write('saleUnitId: $saleUnitId, ')
          ..write(
            'priceReferenceQuantityAtomic: $priceReferenceQuantityAtomic, ',
          )
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InventoryItemsTable extends InventoryItems
    with TableInfo<$InventoryItemsTable, InventoryItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryItemsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _defaultUnitIdMeta = const VerificationMeta(
    'defaultUnitId',
  );
  @override
  late final GeneratedColumn<String> defaultUnitId = GeneratedColumn<String>(
    'default_unit_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES units (unit_id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 160,
    ),
    type: DriftSqlType.string,
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
    defaultUnitId,
    name,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryItemRow> instance, {
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
    if (data.containsKey('default_unit_id')) {
      context.handle(
        _defaultUnitIdMeta,
        defaultUnitId.isAcceptableOrUnknown(
          data['default_unit_id']!,
          _defaultUnitIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_defaultUnitIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InventoryItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryItemRow(
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
      defaultUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}default_unit_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $InventoryItemsTable createAlias(String alias) {
    return $InventoryItemsTable(attachedDatabase, alias);
  }
}

class InventoryItemRow extends DataClass
    implements Insertable<InventoryItemRow> {
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

  /// Unidad elegida para capturar y mostrar existencias del recurso.
  final String defaultUnitId;

  /// Nombre descriptivo; no es único por regla de negocio.
  final String name;
  const InventoryItemRow({
    required this.id,
    required this.active,
    required this.version,
    this.createdEventId,
    this.lastEventId,
    this.lastServerSequence,
    required this.defaultUnitId,
    required this.name,
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
    map['default_unit_id'] = Variable<String>(defaultUnitId);
    map['name'] = Variable<String>(name);
    return map;
  }

  InventoryItemsCompanion toCompanion(bool nullToAbsent) {
    return InventoryItemsCompanion(
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
      defaultUnitId: Value(defaultUnitId),
      name: Value(name),
    );
  }

  factory InventoryItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryItemRow(
      id: serializer.fromJson<String>(json['id']),
      active: serializer.fromJson<bool>(json['active']),
      version: serializer.fromJson<int>(json['version']),
      createdEventId: serializer.fromJson<String?>(json['createdEventId']),
      lastEventId: serializer.fromJson<String?>(json['lastEventId']),
      lastServerSequence: serializer.fromJson<int?>(json['lastServerSequence']),
      defaultUnitId: serializer.fromJson<String>(json['defaultUnitId']),
      name: serializer.fromJson<String>(json['name']),
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
      'defaultUnitId': serializer.toJson<String>(defaultUnitId),
      'name': serializer.toJson<String>(name),
    };
  }

  InventoryItemRow copyWith({
    String? id,
    bool? active,
    int? version,
    Value<String?> createdEventId = const Value.absent(),
    Value<String?> lastEventId = const Value.absent(),
    Value<int?> lastServerSequence = const Value.absent(),
    String? defaultUnitId,
    String? name,
  }) => InventoryItemRow(
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
    defaultUnitId: defaultUnitId ?? this.defaultUnitId,
    name: name ?? this.name,
  );
  InventoryItemRow copyWithCompanion(InventoryItemsCompanion data) {
    return InventoryItemRow(
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
      defaultUnitId: data.defaultUnitId.present
          ? data.defaultUnitId.value
          : this.defaultUnitId,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryItemRow(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('defaultUnitId: $defaultUnitId, ')
          ..write('name: $name')
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
    defaultUnitId,
    name,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryItemRow &&
          other.id == this.id &&
          other.active == this.active &&
          other.version == this.version &&
          other.createdEventId == this.createdEventId &&
          other.lastEventId == this.lastEventId &&
          other.lastServerSequence == this.lastServerSequence &&
          other.defaultUnitId == this.defaultUnitId &&
          other.name == this.name);
}

class InventoryItemsCompanion extends UpdateCompanion<InventoryItemRow> {
  final Value<String> id;
  final Value<bool> active;
  final Value<int> version;
  final Value<String?> createdEventId;
  final Value<String?> lastEventId;
  final Value<int?> lastServerSequence;
  final Value<String> defaultUnitId;
  final Value<String> name;
  final Value<int> rowid;
  const InventoryItemsCompanion({
    this.id = const Value.absent(),
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    this.defaultUnitId = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryItemsCompanion.insert({
    required String id,
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    required String defaultUnitId,
    required String name,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       defaultUnitId = Value(defaultUnitId),
       name = Value(name);
  static Insertable<InventoryItemRow> custom({
    Expression<String>? id,
    Expression<bool>? active,
    Expression<int>? version,
    Expression<String>? createdEventId,
    Expression<String>? lastEventId,
    Expression<int>? lastServerSequence,
    Expression<String>? defaultUnitId,
    Expression<String>? name,
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
      if (defaultUnitId != null) 'default_unit_id': defaultUnitId,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryItemsCompanion copyWith({
    Value<String>? id,
    Value<bool>? active,
    Value<int>? version,
    Value<String?>? createdEventId,
    Value<String?>? lastEventId,
    Value<int?>? lastServerSequence,
    Value<String>? defaultUnitId,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return InventoryItemsCompanion(
      id: id ?? this.id,
      active: active ?? this.active,
      version: version ?? this.version,
      createdEventId: createdEventId ?? this.createdEventId,
      lastEventId: lastEventId ?? this.lastEventId,
      lastServerSequence: lastServerSequence ?? this.lastServerSequence,
      defaultUnitId: defaultUnitId ?? this.defaultUnitId,
      name: name ?? this.name,
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
    if (defaultUnitId.present) {
      map['default_unit_id'] = Variable<String>(defaultUnitId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryItemsCompanion(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('defaultUnitId: $defaultUnitId, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductVariantsTable extends ProductVariants
    with TableInfo<$ProductVariantsTable, ProductVariantRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductVariantsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES products (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameKeyMeta = const VerificationMeta(
    'nameKey',
  );
  @override
  late final GeneratedColumn<String> nameKey = GeneratedColumn<String>(
    'name_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _salePriceMinorMeta = const VerificationMeta(
    'salePriceMinor',
  );
  @override
  late final GeneratedColumn<int> salePriceMinor = GeneratedColumn<int>(
    'sale_price_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _standardCostMinorMeta = const VerificationMeta(
    'standardCostMinor',
  );
  @override
  late final GeneratedColumn<int> standardCostMinor = GeneratedColumn<int>(
    'standard_cost_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _inventoryItemIdMeta = const VerificationMeta(
    'inventoryItemId',
  );
  @override
  late final GeneratedColumn<String> inventoryItemId = GeneratedColumn<String>(
    'inventory_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'UNIQUE REFERENCES inventory_items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
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
    productId,
    name,
    nameKey,
    salePriceMinor,
    standardCostMinor,
    inventoryItemId,
    isDefault,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_variants';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductVariantRow> instance, {
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
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('name_key')) {
      context.handle(
        _nameKeyMeta,
        nameKey.isAcceptableOrUnknown(data['name_key']!, _nameKeyMeta),
      );
    }
    if (data.containsKey('sale_price_minor')) {
      context.handle(
        _salePriceMinorMeta,
        salePriceMinor.isAcceptableOrUnknown(
          data['sale_price_minor']!,
          _salePriceMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_salePriceMinorMeta);
    }
    if (data.containsKey('standard_cost_minor')) {
      context.handle(
        _standardCostMinorMeta,
        standardCostMinor.isAcceptableOrUnknown(
          data['standard_cost_minor']!,
          _standardCostMinorMeta,
        ),
      );
    }
    if (data.containsKey('inventory_item_id')) {
      context.handle(
        _inventoryItemIdMeta,
        inventoryItemId.isAcceptableOrUnknown(
          data['inventory_item_id']!,
          _inventoryItemIdMeta,
        ),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    } else if (isInserting) {
      context.missing(_isDefaultMeta);
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {productId, sortOrder},
    {productId, nameKey},
  ];
  @override
  ProductVariantRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductVariantRow(
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
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      nameKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_key'],
      ),
      salePriceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sale_price_minor'],
      )!,
      standardCostMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}standard_cost_minor'],
      ),
      inventoryItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inventory_item_id'],
      ),
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $ProductVariantsTable createAlias(String alias) {
    return $ProductVariantsTable(attachedDatabase, alias);
  }
}

class ProductVariantRow extends DataClass
    implements Insertable<ProductVariantRow> {
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

  /// Producto propietario de la variante. La cascada solo protege limpiezas
  /// tecnicas de proyecciones; no representa un borrado de negocio.
  final String productId;

  /// Nombre visible normalizado de la variante; null representa una variante
  /// sin nombre capturado.
  final String? name;

  /// Clave NFKC en minúsculas derivada de [name] para unicidad por producto.
  final String? nameKey;

  /// Precio de venta entero expresado en la unidad monetaria menor. Siempre es
  /// positivo y es el único importe obligatorio de la variante.
  final int salePriceMinor;

  /// Costo estándar opcional en unidad monetaria menor. Null significa costo
  /// desconocido y cero significa costo conocido igual a cero.
  final int? standardCostMinor;

  /// Recurso físico cuyo saldo sigue esta variante. Null significa que la
  /// variante no controla existencias. La unicidad mantiene el vínculo directo
  /// uno a uno sin transferir al catálogo la propiedad del recurso.
  final String? inventoryItemId;

  /// Indica que esta es la variante elegida por omisión.
  final bool isDefault;

  /// Posición consecutiva dentro del producto, iniciando en cero.
  final int sortOrder;
  const ProductVariantRow({
    required this.id,
    required this.active,
    required this.version,
    this.createdEventId,
    this.lastEventId,
    this.lastServerSequence,
    required this.productId,
    this.name,
    this.nameKey,
    required this.salePriceMinor,
    this.standardCostMinor,
    this.inventoryItemId,
    required this.isDefault,
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
    map['product_id'] = Variable<String>(productId);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || nameKey != null) {
      map['name_key'] = Variable<String>(nameKey);
    }
    map['sale_price_minor'] = Variable<int>(salePriceMinor);
    if (!nullToAbsent || standardCostMinor != null) {
      map['standard_cost_minor'] = Variable<int>(standardCostMinor);
    }
    if (!nullToAbsent || inventoryItemId != null) {
      map['inventory_item_id'] = Variable<String>(inventoryItemId);
    }
    map['is_default'] = Variable<bool>(isDefault);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  ProductVariantsCompanion toCompanion(bool nullToAbsent) {
    return ProductVariantsCompanion(
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
      productId: Value(productId),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      nameKey: nameKey == null && nullToAbsent
          ? const Value.absent()
          : Value(nameKey),
      salePriceMinor: Value(salePriceMinor),
      standardCostMinor: standardCostMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(standardCostMinor),
      inventoryItemId: inventoryItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(inventoryItemId),
      isDefault: Value(isDefault),
      sortOrder: Value(sortOrder),
    );
  }

  factory ProductVariantRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductVariantRow(
      id: serializer.fromJson<String>(json['id']),
      active: serializer.fromJson<bool>(json['active']),
      version: serializer.fromJson<int>(json['version']),
      createdEventId: serializer.fromJson<String?>(json['createdEventId']),
      lastEventId: serializer.fromJson<String?>(json['lastEventId']),
      lastServerSequence: serializer.fromJson<int?>(json['lastServerSequence']),
      productId: serializer.fromJson<String>(json['productId']),
      name: serializer.fromJson<String?>(json['name']),
      nameKey: serializer.fromJson<String?>(json['nameKey']),
      salePriceMinor: serializer.fromJson<int>(json['salePriceMinor']),
      standardCostMinor: serializer.fromJson<int?>(json['standardCostMinor']),
      inventoryItemId: serializer.fromJson<String?>(json['inventoryItemId']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
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
      'productId': serializer.toJson<String>(productId),
      'name': serializer.toJson<String?>(name),
      'nameKey': serializer.toJson<String?>(nameKey),
      'salePriceMinor': serializer.toJson<int>(salePriceMinor),
      'standardCostMinor': serializer.toJson<int?>(standardCostMinor),
      'inventoryItemId': serializer.toJson<String?>(inventoryItemId),
      'isDefault': serializer.toJson<bool>(isDefault),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  ProductVariantRow copyWith({
    String? id,
    bool? active,
    int? version,
    Value<String?> createdEventId = const Value.absent(),
    Value<String?> lastEventId = const Value.absent(),
    Value<int?> lastServerSequence = const Value.absent(),
    String? productId,
    Value<String?> name = const Value.absent(),
    Value<String?> nameKey = const Value.absent(),
    int? salePriceMinor,
    Value<int?> standardCostMinor = const Value.absent(),
    Value<String?> inventoryItemId = const Value.absent(),
    bool? isDefault,
    int? sortOrder,
  }) => ProductVariantRow(
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
    productId: productId ?? this.productId,
    name: name.present ? name.value : this.name,
    nameKey: nameKey.present ? nameKey.value : this.nameKey,
    salePriceMinor: salePriceMinor ?? this.salePriceMinor,
    standardCostMinor: standardCostMinor.present
        ? standardCostMinor.value
        : this.standardCostMinor,
    inventoryItemId: inventoryItemId.present
        ? inventoryItemId.value
        : this.inventoryItemId,
    isDefault: isDefault ?? this.isDefault,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  ProductVariantRow copyWithCompanion(ProductVariantsCompanion data) {
    return ProductVariantRow(
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
      productId: data.productId.present ? data.productId.value : this.productId,
      name: data.name.present ? data.name.value : this.name,
      nameKey: data.nameKey.present ? data.nameKey.value : this.nameKey,
      salePriceMinor: data.salePriceMinor.present
          ? data.salePriceMinor.value
          : this.salePriceMinor,
      standardCostMinor: data.standardCostMinor.present
          ? data.standardCostMinor.value
          : this.standardCostMinor,
      inventoryItemId: data.inventoryItemId.present
          ? data.inventoryItemId.value
          : this.inventoryItemId,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductVariantRow(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('productId: $productId, ')
          ..write('name: $name, ')
          ..write('nameKey: $nameKey, ')
          ..write('salePriceMinor: $salePriceMinor, ')
          ..write('standardCostMinor: $standardCostMinor, ')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('isDefault: $isDefault, ')
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
    productId,
    name,
    nameKey,
    salePriceMinor,
    standardCostMinor,
    inventoryItemId,
    isDefault,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductVariantRow &&
          other.id == this.id &&
          other.active == this.active &&
          other.version == this.version &&
          other.createdEventId == this.createdEventId &&
          other.lastEventId == this.lastEventId &&
          other.lastServerSequence == this.lastServerSequence &&
          other.productId == this.productId &&
          other.name == this.name &&
          other.nameKey == this.nameKey &&
          other.salePriceMinor == this.salePriceMinor &&
          other.standardCostMinor == this.standardCostMinor &&
          other.inventoryItemId == this.inventoryItemId &&
          other.isDefault == this.isDefault &&
          other.sortOrder == this.sortOrder);
}

class ProductVariantsCompanion extends UpdateCompanion<ProductVariantRow> {
  final Value<String> id;
  final Value<bool> active;
  final Value<int> version;
  final Value<String?> createdEventId;
  final Value<String?> lastEventId;
  final Value<int?> lastServerSequence;
  final Value<String> productId;
  final Value<String?> name;
  final Value<String?> nameKey;
  final Value<int> salePriceMinor;
  final Value<int?> standardCostMinor;
  final Value<String?> inventoryItemId;
  final Value<bool> isDefault;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const ProductVariantsCompanion({
    this.id = const Value.absent(),
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    this.productId = const Value.absent(),
    this.name = const Value.absent(),
    this.nameKey = const Value.absent(),
    this.salePriceMinor = const Value.absent(),
    this.standardCostMinor = const Value.absent(),
    this.inventoryItemId = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductVariantsCompanion.insert({
    required String id,
    this.active = const Value.absent(),
    this.version = const Value.absent(),
    this.createdEventId = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    required String productId,
    this.name = const Value.absent(),
    this.nameKey = const Value.absent(),
    required int salePriceMinor,
    this.standardCostMinor = const Value.absent(),
    this.inventoryItemId = const Value.absent(),
    required bool isDefault,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       productId = Value(productId),
       salePriceMinor = Value(salePriceMinor),
       isDefault = Value(isDefault),
       sortOrder = Value(sortOrder);
  static Insertable<ProductVariantRow> custom({
    Expression<String>? id,
    Expression<bool>? active,
    Expression<int>? version,
    Expression<String>? createdEventId,
    Expression<String>? lastEventId,
    Expression<int>? lastServerSequence,
    Expression<String>? productId,
    Expression<String>? name,
    Expression<String>? nameKey,
    Expression<int>? salePriceMinor,
    Expression<int>? standardCostMinor,
    Expression<String>? inventoryItemId,
    Expression<bool>? isDefault,
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
      if (productId != null) 'product_id': productId,
      if (name != null) 'name': name,
      if (nameKey != null) 'name_key': nameKey,
      if (salePriceMinor != null) 'sale_price_minor': salePriceMinor,
      if (standardCostMinor != null) 'standard_cost_minor': standardCostMinor,
      if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
      if (isDefault != null) 'is_default': isDefault,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductVariantsCompanion copyWith({
    Value<String>? id,
    Value<bool>? active,
    Value<int>? version,
    Value<String?>? createdEventId,
    Value<String?>? lastEventId,
    Value<int?>? lastServerSequence,
    Value<String>? productId,
    Value<String?>? name,
    Value<String?>? nameKey,
    Value<int>? salePriceMinor,
    Value<int?>? standardCostMinor,
    Value<String?>? inventoryItemId,
    Value<bool>? isDefault,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return ProductVariantsCompanion(
      id: id ?? this.id,
      active: active ?? this.active,
      version: version ?? this.version,
      createdEventId: createdEventId ?? this.createdEventId,
      lastEventId: lastEventId ?? this.lastEventId,
      lastServerSequence: lastServerSequence ?? this.lastServerSequence,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      nameKey: nameKey ?? this.nameKey,
      salePriceMinor: salePriceMinor ?? this.salePriceMinor,
      standardCostMinor: standardCostMinor ?? this.standardCostMinor,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      isDefault: isDefault ?? this.isDefault,
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
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nameKey.present) {
      map['name_key'] = Variable<String>(nameKey.value);
    }
    if (salePriceMinor.present) {
      map['sale_price_minor'] = Variable<int>(salePriceMinor.value);
    }
    if (standardCostMinor.present) {
      map['standard_cost_minor'] = Variable<int>(standardCostMinor.value);
    }
    if (inventoryItemId.present) {
      map['inventory_item_id'] = Variable<String>(inventoryItemId.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
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
    return (StringBuffer('ProductVariantsCompanion(')
          ..write('id: $id, ')
          ..write('active: $active, ')
          ..write('version: $version, ')
          ..write('createdEventId: $createdEventId, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('productId: $productId, ')
          ..write('name: $name, ')
          ..write('nameKey: $nameKey, ')
          ..write('salePriceMinor: $salePriceMinor, ')
          ..write('standardCostMinor: $standardCostMinor, ')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('isDefault: $isDefault, ')
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

class $InventoryBalancesTable extends InventoryBalances
    with TableInfo<$InventoryBalancesTable, InventoryBalanceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryBalancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _inventoryItemIdMeta = const VerificationMeta(
    'inventoryItemId',
  );
  @override
  late final GeneratedColumn<String> inventoryItemId = GeneratedColumn<String>(
    'inventory_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES inventory_items (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _quantityOnHandAtomicMeta =
      const VerificationMeta('quantityOnHandAtomic');
  @override
  late final GeneratedColumn<int> quantityOnHandAtomic = GeneratedColumn<int>(
    'quantity_on_hand_atomic',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityAvailableAtomicMeta =
      const VerificationMeta('quantityAvailableAtomic');
  @override
  late final GeneratedColumn<int> quantityAvailableAtomic =
      GeneratedColumn<int>(
        'quantity_available_atomic',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _lastEventIdMeta = const VerificationMeta(
    'lastEventId',
  );
  @override
  late final GeneratedColumn<String> lastEventId = GeneratedColumn<String>(
    'last_event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    inventoryItemId,
    quantityOnHandAtomic,
    quantityAvailableAtomic,
    lastEventId,
    lastServerSequence,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory_balances';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryBalanceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('inventory_item_id')) {
      context.handle(
        _inventoryItemIdMeta,
        inventoryItemId.isAcceptableOrUnknown(
          data['inventory_item_id']!,
          _inventoryItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inventoryItemIdMeta);
    }
    if (data.containsKey('quantity_on_hand_atomic')) {
      context.handle(
        _quantityOnHandAtomicMeta,
        quantityOnHandAtomic.isAcceptableOrUnknown(
          data['quantity_on_hand_atomic']!,
          _quantityOnHandAtomicMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quantityOnHandAtomicMeta);
    }
    if (data.containsKey('quantity_available_atomic')) {
      context.handle(
        _quantityAvailableAtomicMeta,
        quantityAvailableAtomic.isAcceptableOrUnknown(
          data['quantity_available_atomic']!,
          _quantityAvailableAtomicMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quantityAvailableAtomicMeta);
    }
    if (data.containsKey('last_event_id')) {
      context.handle(
        _lastEventIdMeta,
        lastEventId.isAcceptableOrUnknown(
          data['last_event_id']!,
          _lastEventIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastEventIdMeta);
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {inventoryItemId};
  @override
  InventoryBalanceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryBalanceRow(
      inventoryItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inventory_item_id'],
      )!,
      quantityOnHandAtomic: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity_on_hand_atomic'],
      )!,
      quantityAvailableAtomic: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity_available_atomic'],
      )!,
      lastEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_event_id'],
      )!,
      lastServerSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_server_sequence'],
      ),
    );
  }

  @override
  $InventoryBalancesTable createAlias(String alias) {
    return $InventoryBalancesTable(attachedDatabase, alias);
  }
}

class InventoryBalanceRow extends DataClass
    implements Insertable<InventoryBalanceRow> {
  /// Recurso propietario y clave primaria del saldo.
  final String inventoryItemId;

  /// Existencia física expresada exclusivamente en átomos enteros.
  final int quantityOnHandAtomic;

  /// Existencia disponible; en este alcance coincide con la existencia física.
  final int quantityAvailableAtomic;

  /// Último evento que cambió o creó el saldo.
  final String lastEventId;

  /// Secuencia oficial más reciente aplicada al saldo.
  final int? lastServerSequence;
  const InventoryBalanceRow({
    required this.inventoryItemId,
    required this.quantityOnHandAtomic,
    required this.quantityAvailableAtomic,
    required this.lastEventId,
    this.lastServerSequence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['inventory_item_id'] = Variable<String>(inventoryItemId);
    map['quantity_on_hand_atomic'] = Variable<int>(quantityOnHandAtomic);
    map['quantity_available_atomic'] = Variable<int>(quantityAvailableAtomic);
    map['last_event_id'] = Variable<String>(lastEventId);
    if (!nullToAbsent || lastServerSequence != null) {
      map['last_server_sequence'] = Variable<int>(lastServerSequence);
    }
    return map;
  }

  InventoryBalancesCompanion toCompanion(bool nullToAbsent) {
    return InventoryBalancesCompanion(
      inventoryItemId: Value(inventoryItemId),
      quantityOnHandAtomic: Value(quantityOnHandAtomic),
      quantityAvailableAtomic: Value(quantityAvailableAtomic),
      lastEventId: Value(lastEventId),
      lastServerSequence: lastServerSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(lastServerSequence),
    );
  }

  factory InventoryBalanceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryBalanceRow(
      inventoryItemId: serializer.fromJson<String>(json['inventoryItemId']),
      quantityOnHandAtomic: serializer.fromJson<int>(
        json['quantityOnHandAtomic'],
      ),
      quantityAvailableAtomic: serializer.fromJson<int>(
        json['quantityAvailableAtomic'],
      ),
      lastEventId: serializer.fromJson<String>(json['lastEventId']),
      lastServerSequence: serializer.fromJson<int?>(json['lastServerSequence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'inventoryItemId': serializer.toJson<String>(inventoryItemId),
      'quantityOnHandAtomic': serializer.toJson<int>(quantityOnHandAtomic),
      'quantityAvailableAtomic': serializer.toJson<int>(
        quantityAvailableAtomic,
      ),
      'lastEventId': serializer.toJson<String>(lastEventId),
      'lastServerSequence': serializer.toJson<int?>(lastServerSequence),
    };
  }

  InventoryBalanceRow copyWith({
    String? inventoryItemId,
    int? quantityOnHandAtomic,
    int? quantityAvailableAtomic,
    String? lastEventId,
    Value<int?> lastServerSequence = const Value.absent(),
  }) => InventoryBalanceRow(
    inventoryItemId: inventoryItemId ?? this.inventoryItemId,
    quantityOnHandAtomic: quantityOnHandAtomic ?? this.quantityOnHandAtomic,
    quantityAvailableAtomic:
        quantityAvailableAtomic ?? this.quantityAvailableAtomic,
    lastEventId: lastEventId ?? this.lastEventId,
    lastServerSequence: lastServerSequence.present
        ? lastServerSequence.value
        : this.lastServerSequence,
  );
  InventoryBalanceRow copyWithCompanion(InventoryBalancesCompanion data) {
    return InventoryBalanceRow(
      inventoryItemId: data.inventoryItemId.present
          ? data.inventoryItemId.value
          : this.inventoryItemId,
      quantityOnHandAtomic: data.quantityOnHandAtomic.present
          ? data.quantityOnHandAtomic.value
          : this.quantityOnHandAtomic,
      quantityAvailableAtomic: data.quantityAvailableAtomic.present
          ? data.quantityAvailableAtomic.value
          : this.quantityAvailableAtomic,
      lastEventId: data.lastEventId.present
          ? data.lastEventId.value
          : this.lastEventId,
      lastServerSequence: data.lastServerSequence.present
          ? data.lastServerSequence.value
          : this.lastServerSequence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryBalanceRow(')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('quantityOnHandAtomic: $quantityOnHandAtomic, ')
          ..write('quantityAvailableAtomic: $quantityAvailableAtomic, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    inventoryItemId,
    quantityOnHandAtomic,
    quantityAvailableAtomic,
    lastEventId,
    lastServerSequence,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryBalanceRow &&
          other.inventoryItemId == this.inventoryItemId &&
          other.quantityOnHandAtomic == this.quantityOnHandAtomic &&
          other.quantityAvailableAtomic == this.quantityAvailableAtomic &&
          other.lastEventId == this.lastEventId &&
          other.lastServerSequence == this.lastServerSequence);
}

class InventoryBalancesCompanion extends UpdateCompanion<InventoryBalanceRow> {
  final Value<String> inventoryItemId;
  final Value<int> quantityOnHandAtomic;
  final Value<int> quantityAvailableAtomic;
  final Value<String> lastEventId;
  final Value<int?> lastServerSequence;
  final Value<int> rowid;
  const InventoryBalancesCompanion({
    this.inventoryItemId = const Value.absent(),
    this.quantityOnHandAtomic = const Value.absent(),
    this.quantityAvailableAtomic = const Value.absent(),
    this.lastEventId = const Value.absent(),
    this.lastServerSequence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryBalancesCompanion.insert({
    required String inventoryItemId,
    required int quantityOnHandAtomic,
    required int quantityAvailableAtomic,
    required String lastEventId,
    this.lastServerSequence = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : inventoryItemId = Value(inventoryItemId),
       quantityOnHandAtomic = Value(quantityOnHandAtomic),
       quantityAvailableAtomic = Value(quantityAvailableAtomic),
       lastEventId = Value(lastEventId);
  static Insertable<InventoryBalanceRow> custom({
    Expression<String>? inventoryItemId,
    Expression<int>? quantityOnHandAtomic,
    Expression<int>? quantityAvailableAtomic,
    Expression<String>? lastEventId,
    Expression<int>? lastServerSequence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
      if (quantityOnHandAtomic != null)
        'quantity_on_hand_atomic': quantityOnHandAtomic,
      if (quantityAvailableAtomic != null)
        'quantity_available_atomic': quantityAvailableAtomic,
      if (lastEventId != null) 'last_event_id': lastEventId,
      if (lastServerSequence != null)
        'last_server_sequence': lastServerSequence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryBalancesCompanion copyWith({
    Value<String>? inventoryItemId,
    Value<int>? quantityOnHandAtomic,
    Value<int>? quantityAvailableAtomic,
    Value<String>? lastEventId,
    Value<int?>? lastServerSequence,
    Value<int>? rowid,
  }) {
    return InventoryBalancesCompanion(
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      quantityOnHandAtomic: quantityOnHandAtomic ?? this.quantityOnHandAtomic,
      quantityAvailableAtomic:
          quantityAvailableAtomic ?? this.quantityAvailableAtomic,
      lastEventId: lastEventId ?? this.lastEventId,
      lastServerSequence: lastServerSequence ?? this.lastServerSequence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (inventoryItemId.present) {
      map['inventory_item_id'] = Variable<String>(inventoryItemId.value);
    }
    if (quantityOnHandAtomic.present) {
      map['quantity_on_hand_atomic'] = Variable<int>(
        quantityOnHandAtomic.value,
      );
    }
    if (quantityAvailableAtomic.present) {
      map['quantity_available_atomic'] = Variable<int>(
        quantityAvailableAtomic.value,
      );
    }
    if (lastEventId.present) {
      map['last_event_id'] = Variable<String>(lastEventId.value);
    }
    if (lastServerSequence.present) {
      map['last_server_sequence'] = Variable<int>(lastServerSequence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryBalancesCompanion(')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('quantityOnHandAtomic: $quantityOnHandAtomic, ')
          ..write('quantityAvailableAtomic: $quantityAvailableAtomic, ')
          ..write('lastEventId: $lastEventId, ')
          ..write('lastServerSequence: $lastServerSequence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InventoryMovementsTable extends InventoryMovements
    with TableInfo<$InventoryMovementsTable, InventoryMovementRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoryMovementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _movementIdMeta = const VerificationMeta(
    'movementId',
  );
  @override
  late final GeneratedColumn<String> movementId = GeneratedColumn<String>(
    'movement_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inventoryItemIdMeta = const VerificationMeta(
    'inventoryItemId',
  );
  @override
  late final GeneratedColumn<String> inventoryItemId = GeneratedColumn<String>(
    'inventory_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES inventory_items (id) ON DELETE RESTRICT',
    ),
  );
  static const VerificationMeta _saleItemIdMeta = const VerificationMeta(
    'saleItemId',
  );
  @override
  late final GeneratedColumn<String> saleItemId = GeneratedColumn<String>(
    'sale_item_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _reversalOfMovementIdMeta =
      const VerificationMeta('reversalOfMovementId');
  @override
  late final GeneratedColumn<String> reversalOfMovementId =
      GeneratedColumn<String>(
        'reversal_of_movement_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES inventory_movements (movement_id) ON DELETE RESTRICT',
        ),
      );
  static const VerificationMeta _movementTypeMeta = const VerificationMeta(
    'movementType',
  );
  @override
  late final GeneratedColumn<String> movementType = GeneratedColumn<String>(
    'movement_type',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityDeltaAtomicMeta =
      const VerificationMeta('quantityDeltaAtomic');
  @override
  late final GeneratedColumn<int> quantityDeltaAtomic = GeneratedColumn<int>(
    'quantity_delta_atomic',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    $customConstraints: 'NOT NULL CHECK (quantity_delta_atomic <> 0)',
  );
  static const VerificationMeta _totalCostMinorMeta = const VerificationMeta(
    'totalCostMinor',
  );
  @override
  late final GeneratedColumn<int> totalCostMinor = GeneratedColumn<int>(
    'total_cost_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 500,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    movementId,
    inventoryItemId,
    saleItemId,
    eventId,
    reversalOfMovementId,
    movementType,
    quantityDeltaAtomic,
    totalCostMinor,
    reason,
    createdAtLocal,
    serverSequence,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory_movements';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryMovementRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('movement_id')) {
      context.handle(
        _movementIdMeta,
        movementId.isAcceptableOrUnknown(data['movement_id']!, _movementIdMeta),
      );
    } else if (isInserting) {
      context.missing(_movementIdMeta);
    }
    if (data.containsKey('inventory_item_id')) {
      context.handle(
        _inventoryItemIdMeta,
        inventoryItemId.isAcceptableOrUnknown(
          data['inventory_item_id']!,
          _inventoryItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_inventoryItemIdMeta);
    }
    if (data.containsKey('sale_item_id')) {
      context.handle(
        _saleItemIdMeta,
        saleItemId.isAcceptableOrUnknown(
          data['sale_item_id']!,
          _saleItemIdMeta,
        ),
      );
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('reversal_of_movement_id')) {
      context.handle(
        _reversalOfMovementIdMeta,
        reversalOfMovementId.isAcceptableOrUnknown(
          data['reversal_of_movement_id']!,
          _reversalOfMovementIdMeta,
        ),
      );
    }
    if (data.containsKey('movement_type')) {
      context.handle(
        _movementTypeMeta,
        movementType.isAcceptableOrUnknown(
          data['movement_type']!,
          _movementTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_movementTypeMeta);
    }
    if (data.containsKey('quantity_delta_atomic')) {
      context.handle(
        _quantityDeltaAtomicMeta,
        quantityDeltaAtomic.isAcceptableOrUnknown(
          data['quantity_delta_atomic']!,
          _quantityDeltaAtomicMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quantityDeltaAtomicMeta);
    }
    if (data.containsKey('total_cost_minor')) {
      context.handle(
        _totalCostMinorMeta,
        totalCostMinor.isAcceptableOrUnknown(
          data['total_cost_minor']!,
          _totalCostMinorMeta,
        ),
      );
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
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
    if (data.containsKey('server_sequence')) {
      context.handle(
        _serverSequenceMeta,
        serverSequence.isAcceptableOrUnknown(
          data['server_sequence']!,
          _serverSequenceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {movementId};
  @override
  InventoryMovementRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryMovementRow(
      movementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}movement_id'],
      )!,
      inventoryItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inventory_item_id'],
      )!,
      saleItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_item_id'],
      ),
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      reversalOfMovementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reversal_of_movement_id'],
      ),
      movementType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}movement_type'],
      )!,
      quantityDeltaAtomic: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity_delta_atomic'],
      )!,
      totalCostMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_cost_minor'],
      ),
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      createdAtLocal: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_local'],
      )!,
      serverSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_sequence'],
      ),
    );
  }

  @override
  $InventoryMovementsTable createAlias(String alias) {
    return $InventoryMovementsTable(attachedDatabase, alias);
  }
}

class InventoryMovementRow extends DataClass
    implements Insertable<InventoryMovementRow> {
  /// UUID global del movimiento generado en el dispositivo.
  final String movementId;

  /// Recurso cuyo saldo modifica el movimiento.
  final String inventoryItemId;

  /// Renglón de venta causante, cuando el movimiento provenga de una venta.
  final String? saleItemId;

  /// Evento auditable que originó este movimiento.
  final String eventId;

  /// Movimiento original cuando este registro sea una reversión.
  final String? reversalOfMovementId;

  /// Clasificación estable del movimiento; el alta usa `manual_adjustment`.
  final String movementType;

  /// Delta atómico entero, positivo o negativo, pero nunca cero.
  final int quantityDeltaAtomic;

  /// Costo total en unidad monetaria menor, cuando corresponda.
  final int? totalCostMinor;

  /// Explicación obligatoria del ajuste manual.
  final String reason;

  /// Fecha capturada por el dispositivo al crear el movimiento.
  final DateTime createdAtLocal;

  /// Secuencia oficial asignada por el servidor.
  final int? serverSequence;
  const InventoryMovementRow({
    required this.movementId,
    required this.inventoryItemId,
    this.saleItemId,
    required this.eventId,
    this.reversalOfMovementId,
    required this.movementType,
    required this.quantityDeltaAtomic,
    this.totalCostMinor,
    required this.reason,
    required this.createdAtLocal,
    this.serverSequence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['movement_id'] = Variable<String>(movementId);
    map['inventory_item_id'] = Variable<String>(inventoryItemId);
    if (!nullToAbsent || saleItemId != null) {
      map['sale_item_id'] = Variable<String>(saleItemId);
    }
    map['event_id'] = Variable<String>(eventId);
    if (!nullToAbsent || reversalOfMovementId != null) {
      map['reversal_of_movement_id'] = Variable<String>(reversalOfMovementId);
    }
    map['movement_type'] = Variable<String>(movementType);
    map['quantity_delta_atomic'] = Variable<int>(quantityDeltaAtomic);
    if (!nullToAbsent || totalCostMinor != null) {
      map['total_cost_minor'] = Variable<int>(totalCostMinor);
    }
    map['reason'] = Variable<String>(reason);
    map['created_at_local'] = Variable<DateTime>(createdAtLocal);
    if (!nullToAbsent || serverSequence != null) {
      map['server_sequence'] = Variable<int>(serverSequence);
    }
    return map;
  }

  InventoryMovementsCompanion toCompanion(bool nullToAbsent) {
    return InventoryMovementsCompanion(
      movementId: Value(movementId),
      inventoryItemId: Value(inventoryItemId),
      saleItemId: saleItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(saleItemId),
      eventId: Value(eventId),
      reversalOfMovementId: reversalOfMovementId == null && nullToAbsent
          ? const Value.absent()
          : Value(reversalOfMovementId),
      movementType: Value(movementType),
      quantityDeltaAtomic: Value(quantityDeltaAtomic),
      totalCostMinor: totalCostMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(totalCostMinor),
      reason: Value(reason),
      createdAtLocal: Value(createdAtLocal),
      serverSequence: serverSequence == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSequence),
    );
  }

  factory InventoryMovementRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryMovementRow(
      movementId: serializer.fromJson<String>(json['movementId']),
      inventoryItemId: serializer.fromJson<String>(json['inventoryItemId']),
      saleItemId: serializer.fromJson<String?>(json['saleItemId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      reversalOfMovementId: serializer.fromJson<String?>(
        json['reversalOfMovementId'],
      ),
      movementType: serializer.fromJson<String>(json['movementType']),
      quantityDeltaAtomic: serializer.fromJson<int>(
        json['quantityDeltaAtomic'],
      ),
      totalCostMinor: serializer.fromJson<int?>(json['totalCostMinor']),
      reason: serializer.fromJson<String>(json['reason']),
      createdAtLocal: serializer.fromJson<DateTime>(json['createdAtLocal']),
      serverSequence: serializer.fromJson<int?>(json['serverSequence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'movementId': serializer.toJson<String>(movementId),
      'inventoryItemId': serializer.toJson<String>(inventoryItemId),
      'saleItemId': serializer.toJson<String?>(saleItemId),
      'eventId': serializer.toJson<String>(eventId),
      'reversalOfMovementId': serializer.toJson<String?>(reversalOfMovementId),
      'movementType': serializer.toJson<String>(movementType),
      'quantityDeltaAtomic': serializer.toJson<int>(quantityDeltaAtomic),
      'totalCostMinor': serializer.toJson<int?>(totalCostMinor),
      'reason': serializer.toJson<String>(reason),
      'createdAtLocal': serializer.toJson<DateTime>(createdAtLocal),
      'serverSequence': serializer.toJson<int?>(serverSequence),
    };
  }

  InventoryMovementRow copyWith({
    String? movementId,
    String? inventoryItemId,
    Value<String?> saleItemId = const Value.absent(),
    String? eventId,
    Value<String?> reversalOfMovementId = const Value.absent(),
    String? movementType,
    int? quantityDeltaAtomic,
    Value<int?> totalCostMinor = const Value.absent(),
    String? reason,
    DateTime? createdAtLocal,
    Value<int?> serverSequence = const Value.absent(),
  }) => InventoryMovementRow(
    movementId: movementId ?? this.movementId,
    inventoryItemId: inventoryItemId ?? this.inventoryItemId,
    saleItemId: saleItemId.present ? saleItemId.value : this.saleItemId,
    eventId: eventId ?? this.eventId,
    reversalOfMovementId: reversalOfMovementId.present
        ? reversalOfMovementId.value
        : this.reversalOfMovementId,
    movementType: movementType ?? this.movementType,
    quantityDeltaAtomic: quantityDeltaAtomic ?? this.quantityDeltaAtomic,
    totalCostMinor: totalCostMinor.present
        ? totalCostMinor.value
        : this.totalCostMinor,
    reason: reason ?? this.reason,
    createdAtLocal: createdAtLocal ?? this.createdAtLocal,
    serverSequence: serverSequence.present
        ? serverSequence.value
        : this.serverSequence,
  );
  InventoryMovementRow copyWithCompanion(InventoryMovementsCompanion data) {
    return InventoryMovementRow(
      movementId: data.movementId.present
          ? data.movementId.value
          : this.movementId,
      inventoryItemId: data.inventoryItemId.present
          ? data.inventoryItemId.value
          : this.inventoryItemId,
      saleItemId: data.saleItemId.present
          ? data.saleItemId.value
          : this.saleItemId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      reversalOfMovementId: data.reversalOfMovementId.present
          ? data.reversalOfMovementId.value
          : this.reversalOfMovementId,
      movementType: data.movementType.present
          ? data.movementType.value
          : this.movementType,
      quantityDeltaAtomic: data.quantityDeltaAtomic.present
          ? data.quantityDeltaAtomic.value
          : this.quantityDeltaAtomic,
      totalCostMinor: data.totalCostMinor.present
          ? data.totalCostMinor.value
          : this.totalCostMinor,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdAtLocal: data.createdAtLocal.present
          ? data.createdAtLocal.value
          : this.createdAtLocal,
      serverSequence: data.serverSequence.present
          ? data.serverSequence.value
          : this.serverSequence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryMovementRow(')
          ..write('movementId: $movementId, ')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('saleItemId: $saleItemId, ')
          ..write('eventId: $eventId, ')
          ..write('reversalOfMovementId: $reversalOfMovementId, ')
          ..write('movementType: $movementType, ')
          ..write('quantityDeltaAtomic: $quantityDeltaAtomic, ')
          ..write('totalCostMinor: $totalCostMinor, ')
          ..write('reason: $reason, ')
          ..write('createdAtLocal: $createdAtLocal, ')
          ..write('serverSequence: $serverSequence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    movementId,
    inventoryItemId,
    saleItemId,
    eventId,
    reversalOfMovementId,
    movementType,
    quantityDeltaAtomic,
    totalCostMinor,
    reason,
    createdAtLocal,
    serverSequence,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryMovementRow &&
          other.movementId == this.movementId &&
          other.inventoryItemId == this.inventoryItemId &&
          other.saleItemId == this.saleItemId &&
          other.eventId == this.eventId &&
          other.reversalOfMovementId == this.reversalOfMovementId &&
          other.movementType == this.movementType &&
          other.quantityDeltaAtomic == this.quantityDeltaAtomic &&
          other.totalCostMinor == this.totalCostMinor &&
          other.reason == this.reason &&
          other.createdAtLocal == this.createdAtLocal &&
          other.serverSequence == this.serverSequence);
}

class InventoryMovementsCompanion
    extends UpdateCompanion<InventoryMovementRow> {
  final Value<String> movementId;
  final Value<String> inventoryItemId;
  final Value<String?> saleItemId;
  final Value<String> eventId;
  final Value<String?> reversalOfMovementId;
  final Value<String> movementType;
  final Value<int> quantityDeltaAtomic;
  final Value<int?> totalCostMinor;
  final Value<String> reason;
  final Value<DateTime> createdAtLocal;
  final Value<int?> serverSequence;
  final Value<int> rowid;
  const InventoryMovementsCompanion({
    this.movementId = const Value.absent(),
    this.inventoryItemId = const Value.absent(),
    this.saleItemId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.reversalOfMovementId = const Value.absent(),
    this.movementType = const Value.absent(),
    this.quantityDeltaAtomic = const Value.absent(),
    this.totalCostMinor = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAtLocal = const Value.absent(),
    this.serverSequence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoryMovementsCompanion.insert({
    required String movementId,
    required String inventoryItemId,
    this.saleItemId = const Value.absent(),
    required String eventId,
    this.reversalOfMovementId = const Value.absent(),
    required String movementType,
    required int quantityDeltaAtomic,
    this.totalCostMinor = const Value.absent(),
    required String reason,
    required DateTime createdAtLocal,
    this.serverSequence = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : movementId = Value(movementId),
       inventoryItemId = Value(inventoryItemId),
       eventId = Value(eventId),
       movementType = Value(movementType),
       quantityDeltaAtomic = Value(quantityDeltaAtomic),
       reason = Value(reason),
       createdAtLocal = Value(createdAtLocal);
  static Insertable<InventoryMovementRow> custom({
    Expression<String>? movementId,
    Expression<String>? inventoryItemId,
    Expression<String>? saleItemId,
    Expression<String>? eventId,
    Expression<String>? reversalOfMovementId,
    Expression<String>? movementType,
    Expression<int>? quantityDeltaAtomic,
    Expression<int>? totalCostMinor,
    Expression<String>? reason,
    Expression<DateTime>? createdAtLocal,
    Expression<int>? serverSequence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (movementId != null) 'movement_id': movementId,
      if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
      if (saleItemId != null) 'sale_item_id': saleItemId,
      if (eventId != null) 'event_id': eventId,
      if (reversalOfMovementId != null)
        'reversal_of_movement_id': reversalOfMovementId,
      if (movementType != null) 'movement_type': movementType,
      if (quantityDeltaAtomic != null)
        'quantity_delta_atomic': quantityDeltaAtomic,
      if (totalCostMinor != null) 'total_cost_minor': totalCostMinor,
      if (reason != null) 'reason': reason,
      if (createdAtLocal != null) 'created_at_local': createdAtLocal,
      if (serverSequence != null) 'server_sequence': serverSequence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoryMovementsCompanion copyWith({
    Value<String>? movementId,
    Value<String>? inventoryItemId,
    Value<String?>? saleItemId,
    Value<String>? eventId,
    Value<String?>? reversalOfMovementId,
    Value<String>? movementType,
    Value<int>? quantityDeltaAtomic,
    Value<int?>? totalCostMinor,
    Value<String>? reason,
    Value<DateTime>? createdAtLocal,
    Value<int?>? serverSequence,
    Value<int>? rowid,
  }) {
    return InventoryMovementsCompanion(
      movementId: movementId ?? this.movementId,
      inventoryItemId: inventoryItemId ?? this.inventoryItemId,
      saleItemId: saleItemId ?? this.saleItemId,
      eventId: eventId ?? this.eventId,
      reversalOfMovementId: reversalOfMovementId ?? this.reversalOfMovementId,
      movementType: movementType ?? this.movementType,
      quantityDeltaAtomic: quantityDeltaAtomic ?? this.quantityDeltaAtomic,
      totalCostMinor: totalCostMinor ?? this.totalCostMinor,
      reason: reason ?? this.reason,
      createdAtLocal: createdAtLocal ?? this.createdAtLocal,
      serverSequence: serverSequence ?? this.serverSequence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (movementId.present) {
      map['movement_id'] = Variable<String>(movementId.value);
    }
    if (inventoryItemId.present) {
      map['inventory_item_id'] = Variable<String>(inventoryItemId.value);
    }
    if (saleItemId.present) {
      map['sale_item_id'] = Variable<String>(saleItemId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (reversalOfMovementId.present) {
      map['reversal_of_movement_id'] = Variable<String>(
        reversalOfMovementId.value,
      );
    }
    if (movementType.present) {
      map['movement_type'] = Variable<String>(movementType.value);
    }
    if (quantityDeltaAtomic.present) {
      map['quantity_delta_atomic'] = Variable<int>(quantityDeltaAtomic.value);
    }
    if (totalCostMinor.present) {
      map['total_cost_minor'] = Variable<int>(totalCostMinor.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (createdAtLocal.present) {
      map['created_at_local'] = Variable<DateTime>(createdAtLocal.value);
    }
    if (serverSequence.present) {
      map['server_sequence'] = Variable<int>(serverSequence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoryMovementsCompanion(')
          ..write('movementId: $movementId, ')
          ..write('inventoryItemId: $inventoryItemId, ')
          ..write('saleItemId: $saleItemId, ')
          ..write('eventId: $eventId, ')
          ..write('reversalOfMovementId: $reversalOfMovementId, ')
          ..write('movementType: $movementType, ')
          ..write('quantityDeltaAtomic: $quantityDeltaAtomic, ')
          ..write('totalCostMinor: $totalCostMinor, ')
          ..write('reason: $reason, ')
          ..write('createdAtLocal: $createdAtLocal, ')
          ..write('serverSequence: $serverSequence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $UnitsTable units = $UnitsTable(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $InventoryItemsTable inventoryItems = $InventoryItemsTable(this);
  late final $ProductVariantsTable productVariants = $ProductVariantsTable(
    this,
  );
  late final $EspaciosTable espacios = $EspaciosTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $EventRefsTable eventRefs = $EventRefsTable(this);
  late final $SyncCheckpointsTable syncCheckpoints = $SyncCheckpointsTable(
    this,
  );
  late final $InventoryBalancesTable inventoryBalances =
      $InventoryBalancesTable(this);
  late final $InventoryMovementsTable inventoryMovements =
      $InventoryMovementsTable(this);
  late final Index idxEspaciosIdentificacionUnique = Index(
    'idx_espacios_identificacion_unique',
    'CREATE UNIQUE INDEX idx_espacios_identificacion_unique ON espacios (identificacion) WHERE identificacion IS NOT NULL AND identificacion != \'\'',
  );
  late final CategoriaDao categoriaDao = CategoriaDao(this as AppDatabase);
  late final ProductoDao productoDao = ProductoDao(this as AppDatabase);
  late final EspacioDao espacioDao = EspacioDao(this as AppDatabase);
  late final EventDao eventDao = EventDao(this as AppDatabase);
  late final EventRefDao eventRefDao = EventRefDao(this as AppDatabase);
  late final SyncCheckpointDao syncCheckpointDao = SyncCheckpointDao(
    this as AppDatabase,
  );
  late final UnitDao unitDao = UnitDao(this as AppDatabase);
  late final InventoryDao inventoryDao = InventoryDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categories,
    units,
    products,
    inventoryItems,
    productVariants,
    espacios,
    events,
    eventRefs,
    syncCheckpoints,
    inventoryBalances,
    inventoryMovements,
    idxEspaciosIdentificacionUnique,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'products',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('product_variants', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'inventory_items',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('inventory_balances', kind: UpdateKind.delete)],
    ),
  ]);
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

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProductsTable, List<ProductRow>>
  _productsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.products,
    aliasName: 'categories__id__products__category_id',
  );

  $$ProductsTableProcessedTableManager get productsRefs {
    final manager = $$ProductsTableTableManager(
      $_db,
      $_db.products,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_productsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

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

  Expression<bool> productsRefs(
    Expression<bool> Function($$ProductsTableFilterComposer f) f,
  ) {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
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

  Expression<T> productsRefs<T extends Object>(
    Expression<T> Function($$ProductsTableAnnotationComposer a) f,
  ) {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
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
          (CategoryRow, $$CategoriesTableReferences),
          CategoryRow,
          PrefetchHooks Function({bool productsRefs})
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
              .map(
                (e) => (
                  e.readTable(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({productsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (productsRefs) db.products],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (productsRefs)
                    await $_getPrefetchedData<
                      CategoryRow,
                      $CategoriesTable,
                      ProductRow
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._productsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CategoriesTableReferences(
                            db,
                            table,
                            p0,
                          ).productsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.categoryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
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
      (CategoryRow, $$CategoriesTableReferences),
      CategoryRow,
      PrefetchHooks Function({bool productsRefs})
    >;
typedef $$UnitsTableCreateCompanionBuilder =
    UnitsCompanion Function({
      required String unitId,
      required String code,
      required String name,
      required String symbol,
      required String dimension,
      required int atomicFactor,
      required int maxFractionDigits,
      Value<bool> active,
      Value<int> rowid,
    });
typedef $$UnitsTableUpdateCompanionBuilder =
    UnitsCompanion Function({
      Value<String> unitId,
      Value<String> code,
      Value<String> name,
      Value<String> symbol,
      Value<String> dimension,
      Value<int> atomicFactor,
      Value<int> maxFractionDigits,
      Value<bool> active,
      Value<int> rowid,
    });

final class $$UnitsTableReferences
    extends BaseReferences<_$AppDatabase, $UnitsTable, UnitRow> {
  $$UnitsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ProductsTable, List<ProductRow>>
  _productsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.products,
    aliasName: 'units__unit_id__products__sale_unit_id',
  );

  $$ProductsTableProcessedTableManager get productsRefs {
    final manager = $$ProductsTableTableManager($_db, $_db.products).filter(
      (f) => f.saleUnitId.unitId.sqlEquals($_itemColumn<String>('unit_id')!),
    );

    final cache = $_typedResult.readTableOrNull(_productsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$InventoryItemsTable, List<InventoryItemRow>>
  _inventoryItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.inventoryItems,
    aliasName: 'units__unit_id__inventory_items__default_unit_id',
  );

  $$InventoryItemsTableProcessedTableManager get inventoryItemsRefs {
    final manager = $$InventoryItemsTableTableManager($_db, $_db.inventoryItems)
        .filter(
          (f) => f.defaultUnitId.unitId.sqlEquals(
            $_itemColumn<String>('unit_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(_inventoryItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$UnitsTableFilterComposer extends Composer<_$AppDatabase, $UnitsTable> {
  $$UnitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get unitId => $composableBuilder(
    column: $table.unitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dimension => $composableBuilder(
    column: $table.dimension,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get atomicFactor => $composableBuilder(
    column: $table.atomicFactor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maxFractionDigits => $composableBuilder(
    column: $table.maxFractionDigits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> productsRefs(
    Expression<bool> Function($$ProductsTableFilterComposer f) f,
  ) {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.saleUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> inventoryItemsRefs(
    Expression<bool> Function($$InventoryItemsTableFilterComposer f) f,
  ) {
    final $$InventoryItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.defaultUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UnitsTableOrderingComposer
    extends Composer<_$AppDatabase, $UnitsTable> {
  $$UnitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get unitId => $composableBuilder(
    column: $table.unitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dimension => $composableBuilder(
    column: $table.dimension,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get atomicFactor => $composableBuilder(
    column: $table.atomicFactor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maxFractionDigits => $composableBuilder(
    column: $table.maxFractionDigits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UnitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UnitsTable> {
  $$UnitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get unitId =>
      $composableBuilder(column: $table.unitId, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get dimension =>
      $composableBuilder(column: $table.dimension, builder: (column) => column);

  GeneratedColumn<int> get atomicFactor => $composableBuilder(
    column: $table.atomicFactor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maxFractionDigits => $composableBuilder(
    column: $table.maxFractionDigits,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  Expression<T> productsRefs<T extends Object>(
    Expression<T> Function($$ProductsTableAnnotationComposer a) f,
  ) {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.saleUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> inventoryItemsRefs<T extends Object>(
    Expression<T> Function($$InventoryItemsTableAnnotationComposer a) f,
  ) {
    final $$InventoryItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.unitId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.defaultUnitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$UnitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UnitsTable,
          UnitRow,
          $$UnitsTableFilterComposer,
          $$UnitsTableOrderingComposer,
          $$UnitsTableAnnotationComposer,
          $$UnitsTableCreateCompanionBuilder,
          $$UnitsTableUpdateCompanionBuilder,
          (UnitRow, $$UnitsTableReferences),
          UnitRow,
          PrefetchHooks Function({bool productsRefs, bool inventoryItemsRefs})
        > {
  $$UnitsTableTableManager(_$AppDatabase db, $UnitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UnitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UnitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UnitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> unitId = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> symbol = const Value.absent(),
                Value<String> dimension = const Value.absent(),
                Value<int> atomicFactor = const Value.absent(),
                Value<int> maxFractionDigits = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UnitsCompanion(
                unitId: unitId,
                code: code,
                name: name,
                symbol: symbol,
                dimension: dimension,
                atomicFactor: atomicFactor,
                maxFractionDigits: maxFractionDigits,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String unitId,
                required String code,
                required String name,
                required String symbol,
                required String dimension,
                required int atomicFactor,
                required int maxFractionDigits,
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UnitsCompanion.insert(
                unitId: unitId,
                code: code,
                name: name,
                symbol: symbol,
                dimension: dimension,
                atomicFactor: atomicFactor,
                maxFractionDigits: maxFractionDigits,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$UnitsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({productsRefs = false, inventoryItemsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (productsRefs) db.products,
                    if (inventoryItemsRefs) db.inventoryItems,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (productsRefs)
                        await $_getPrefetchedData<
                          UnitRow,
                          $UnitsTable,
                          ProductRow
                        >(
                          currentTable: table,
                          referencedTable: $$UnitsTableReferences
                              ._productsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UnitsTableReferences(
                                db,
                                table,
                                p0,
                              ).productsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.saleUnitId == item.unitId,
                              ),
                          typedResults: items,
                        ),
                      if (inventoryItemsRefs)
                        await $_getPrefetchedData<
                          UnitRow,
                          $UnitsTable,
                          InventoryItemRow
                        >(
                          currentTable: table,
                          referencedTable: $$UnitsTableReferences
                              ._inventoryItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$UnitsTableReferences(
                                db,
                                table,
                                p0,
                              ).inventoryItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.defaultUnitId == item.unitId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$UnitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UnitsTable,
      UnitRow,
      $$UnitsTableFilterComposer,
      $$UnitsTableOrderingComposer,
      $$UnitsTableAnnotationComposer,
      $$UnitsTableCreateCompanionBuilder,
      $$UnitsTableUpdateCompanionBuilder,
      (UnitRow, $$UnitsTableReferences),
      UnitRow,
      PrefetchHooks Function({bool productsRefs, bool inventoryItemsRefs})
    >;
typedef $$ProductsTableCreateCompanionBuilder =
    ProductsCompanion Function({
      required String id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      required String name,
      Value<String?> categoryId,
      Value<String> saleMode,
      Value<String?> saleUnitId,
      Value<int?> priceReferenceQuantityAtomic,
      Value<int> rowid,
    });
typedef $$ProductsTableUpdateCompanionBuilder =
    ProductsCompanion Function({
      Value<String> id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      Value<String> name,
      Value<String?> categoryId,
      Value<String> saleMode,
      Value<String?> saleUnitId,
      Value<int?> priceReferenceQuantityAtomic,
      Value<int> rowid,
    });

final class $$ProductsTableReferences
    extends BaseReferences<_$AppDatabase, $ProductsTable, ProductRow> {
  $$ProductsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('products__category_id__categories__id');

  $$CategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $UnitsTable _saleUnitIdTable(_$AppDatabase db) =>
      db.units.createAlias('products__sale_unit_id__units__unit_id');

  $$UnitsTableProcessedTableManager? get saleUnitId {
    final $_column = $_itemColumn<String>('sale_unit_id');
    if ($_column == null) return null;
    final manager = $$UnitsTableTableManager(
      $_db,
      $_db.units,
    ).filter((f) => f.unitId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_saleUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ProductVariantsTable, List<ProductVariantRow>>
  _productVariantsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.productVariants,
    aliasName: 'products__id__product_variants__product_id',
  );

  $$ProductVariantsTableProcessedTableManager get productVariantsRefs {
    final manager = $$ProductVariantsTableTableManager(
      $_db,
      $_db.productVariants,
    ).filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _productVariantsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
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

  ColumnFilters<String> get saleMode => $composableBuilder(
    column: $table.saleMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceReferenceQuantityAtomic => $composableBuilder(
    column: $table.priceReferenceQuantityAtomic,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UnitsTableFilterComposer get saleUnitId {
    final $$UnitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleUnitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableFilterComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> productVariantsRefs(
    Expression<bool> Function($$ProductVariantsTableFilterComposer f) f,
  ) {
    final $$ProductVariantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableFilterComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
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

  ColumnOrderings<String> get saleMode => $composableBuilder(
    column: $table.saleMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceReferenceQuantityAtomic => $composableBuilder(
    column: $table.priceReferenceQuantityAtomic,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UnitsTableOrderingComposer get saleUnitId {
    final $$UnitsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleUnitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableOrderingComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
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

  GeneratedColumn<String> get saleMode =>
      $composableBuilder(column: $table.saleMode, builder: (column) => column);

  GeneratedColumn<int> get priceReferenceQuantityAtomic => $composableBuilder(
    column: $table.priceReferenceQuantityAtomic,
    builder: (column) => column,
  );

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$UnitsTableAnnotationComposer get saleUnitId {
    final $$UnitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.saleUnitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableAnnotationComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> productVariantsRefs<T extends Object>(
    Expression<T> Function($$ProductVariantsTableAnnotationComposer a) f,
  ) {
    final $$ProductVariantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.productId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableAnnotationComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductsTable,
          ProductRow,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (ProductRow, $$ProductsTableReferences),
          ProductRow,
          PrefetchHooks Function({
            bool categoryId,
            bool saleUnitId,
            bool productVariantsRefs,
          })
        > {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> createdEventId = const Value.absent(),
                Value<String?> lastEventId = const Value.absent(),
                Value<int?> lastServerSequence = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String> saleMode = const Value.absent(),
                Value<String?> saleUnitId = const Value.absent(),
                Value<int?> priceReferenceQuantityAtomic = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                name: name,
                categoryId: categoryId,
                saleMode: saleMode,
                saleUnitId: saleUnitId,
                priceReferenceQuantityAtomic: priceReferenceQuantityAtomic,
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
                Value<String?> categoryId = const Value.absent(),
                Value<String> saleMode = const Value.absent(),
                Value<String?> saleUnitId = const Value.absent(),
                Value<int?> priceReferenceQuantityAtomic = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion.insert(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                name: name,
                categoryId: categoryId,
                saleMode: saleMode,
                saleUnitId: saleUnitId,
                priceReferenceQuantityAtomic: priceReferenceQuantityAtomic,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProductsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                categoryId = false,
                saleUnitId = false,
                productVariantsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (productVariantsRefs) db.productVariants,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (categoryId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.categoryId,
                                    referencedTable: $$ProductsTableReferences
                                        ._categoryIdTable(db),
                                    referencedColumn: $$ProductsTableReferences
                                        ._categoryIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (saleUnitId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.saleUnitId,
                                    referencedTable: $$ProductsTableReferences
                                        ._saleUnitIdTable(db),
                                    referencedColumn: $$ProductsTableReferences
                                        ._saleUnitIdTable(db)
                                        .unitId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (productVariantsRefs)
                        await $_getPrefetchedData<
                          ProductRow,
                          $ProductsTable,
                          ProductVariantRow
                        >(
                          currentTable: table,
                          referencedTable: $$ProductsTableReferences
                              ._productVariantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProductsTableReferences(
                                db,
                                table,
                                p0,
                              ).productVariantsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.productId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductsTable,
      ProductRow,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (ProductRow, $$ProductsTableReferences),
      ProductRow,
      PrefetchHooks Function({
        bool categoryId,
        bool saleUnitId,
        bool productVariantsRefs,
      })
    >;
typedef $$InventoryItemsTableCreateCompanionBuilder =
    InventoryItemsCompanion Function({
      required String id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      required String defaultUnitId,
      required String name,
      Value<int> rowid,
    });
typedef $$InventoryItemsTableUpdateCompanionBuilder =
    InventoryItemsCompanion Function({
      Value<String> id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      Value<String> defaultUnitId,
      Value<String> name,
      Value<int> rowid,
    });

final class $$InventoryItemsTableReferences
    extends
        BaseReferences<_$AppDatabase, $InventoryItemsTable, InventoryItemRow> {
  $$InventoryItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $UnitsTable _defaultUnitIdTable(_$AppDatabase db) =>
      db.units.createAlias('inventory_items__default_unit_id__units__unit_id');

  $$UnitsTableProcessedTableManager get defaultUnitId {
    final $_column = $_itemColumn<String>('default_unit_id')!;

    final manager = $$UnitsTableTableManager(
      $_db,
      $_db.units,
    ).filter((f) => f.unitId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_defaultUnitIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ProductVariantsTable, List<ProductVariantRow>>
  _productVariantsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.productVariants,
    aliasName: 'inventory_items__id__product_variants__inventory_item_id',
  );

  $$ProductVariantsTableProcessedTableManager get productVariantsRefs {
    final manager =
        $$ProductVariantsTableTableManager($_db, $_db.productVariants).filter(
          (f) => f.inventoryItemId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _productVariantsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$InventoryBalancesTable, List<InventoryBalanceRow>>
  _inventoryBalancesRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.inventoryBalances,
        aliasName: 'inventory_items__id__inventory_balances__inventory_item_id',
      );

  $$InventoryBalancesTableProcessedTableManager get inventoryBalancesRefs {
    final manager =
        $$InventoryBalancesTableTableManager(
          $_db,
          $_db.inventoryBalances,
        ).filter(
          (f) => f.inventoryItemId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _inventoryBalancesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $InventoryMovementsTable,
    List<InventoryMovementRow>
  >
  _inventoryMovementsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.inventoryMovements,
        aliasName:
            'inventory_items__id__inventory_movements__inventory_item_id',
      );

  $$InventoryMovementsTableProcessedTableManager get inventoryMovementsRefs {
    final manager =
        $$InventoryMovementsTableTableManager(
          $_db,
          $_db.inventoryMovements,
        ).filter(
          (f) => f.inventoryItemId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _inventoryMovementsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$InventoryItemsTableFilterComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableFilterComposer({
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

  $$UnitsTableFilterComposer get defaultUnitId {
    final $$UnitsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.defaultUnitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableFilterComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> productVariantsRefs(
    Expression<bool> Function($$ProductVariantsTableFilterComposer f) f,
  ) {
    final $$ProductVariantsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.inventoryItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableFilterComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> inventoryBalancesRefs(
    Expression<bool> Function($$InventoryBalancesTableFilterComposer f) f,
  ) {
    final $$InventoryBalancesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.inventoryBalances,
      getReferencedColumn: (t) => t.inventoryItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryBalancesTableFilterComposer(
            $db: $db,
            $table: $db.inventoryBalances,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> inventoryMovementsRefs(
    Expression<bool> Function($$InventoryMovementsTableFilterComposer f) f,
  ) {
    final $$InventoryMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.inventoryItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$InventoryItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableOrderingComposer({
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

  $$UnitsTableOrderingComposer get defaultUnitId {
    final $$UnitsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.defaultUnitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableOrderingComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InventoryItemsTable> {
  $$InventoryItemsTableAnnotationComposer({
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

  $$UnitsTableAnnotationComposer get defaultUnitId {
    final $$UnitsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.defaultUnitId,
      referencedTable: $db.units,
      getReferencedColumn: (t) => t.unitId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$UnitsTableAnnotationComposer(
            $db: $db,
            $table: $db.units,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> productVariantsRefs<T extends Object>(
    Expression<T> Function($$ProductVariantsTableAnnotationComposer a) f,
  ) {
    final $$ProductVariantsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.productVariants,
      getReferencedColumn: (t) => t.inventoryItemId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductVariantsTableAnnotationComposer(
            $db: $db,
            $table: $db.productVariants,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> inventoryBalancesRefs<T extends Object>(
    Expression<T> Function($$InventoryBalancesTableAnnotationComposer a) f,
  ) {
    final $$InventoryBalancesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.inventoryBalances,
          getReferencedColumn: (t) => t.inventoryItemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryBalancesTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryBalances,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> inventoryMovementsRefs<T extends Object>(
    Expression<T> Function($$InventoryMovementsTableAnnotationComposer a) f,
  ) {
    final $$InventoryMovementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.inventoryMovements,
          getReferencedColumn: (t) => t.inventoryItemId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryMovementsTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryMovements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$InventoryItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InventoryItemsTable,
          InventoryItemRow,
          $$InventoryItemsTableFilterComposer,
          $$InventoryItemsTableOrderingComposer,
          $$InventoryItemsTableAnnotationComposer,
          $$InventoryItemsTableCreateCompanionBuilder,
          $$InventoryItemsTableUpdateCompanionBuilder,
          (InventoryItemRow, $$InventoryItemsTableReferences),
          InventoryItemRow,
          PrefetchHooks Function({
            bool defaultUnitId,
            bool productVariantsRefs,
            bool inventoryBalancesRefs,
            bool inventoryMovementsRefs,
          })
        > {
  $$InventoryItemsTableTableManager(
    _$AppDatabase db,
    $InventoryItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoryItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoryItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> createdEventId = const Value.absent(),
                Value<String?> lastEventId = const Value.absent(),
                Value<int?> lastServerSequence = const Value.absent(),
                Value<String> defaultUnitId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryItemsCompanion(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                defaultUnitId: defaultUnitId,
                name: name,
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
                required String defaultUnitId,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) => InventoryItemsCompanion.insert(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                defaultUnitId: defaultUnitId,
                name: name,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$InventoryItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                defaultUnitId = false,
                productVariantsRefs = false,
                inventoryBalancesRefs = false,
                inventoryMovementsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (productVariantsRefs) db.productVariants,
                    if (inventoryBalancesRefs) db.inventoryBalances,
                    if (inventoryMovementsRefs) db.inventoryMovements,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (defaultUnitId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.defaultUnitId,
                                    referencedTable:
                                        $$InventoryItemsTableReferences
                                            ._defaultUnitIdTable(db),
                                    referencedColumn:
                                        $$InventoryItemsTableReferences
                                            ._defaultUnitIdTable(db)
                                            .unitId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (productVariantsRefs)
                        await $_getPrefetchedData<
                          InventoryItemRow,
                          $InventoryItemsTable,
                          ProductVariantRow
                        >(
                          currentTable: table,
                          referencedTable: $$InventoryItemsTableReferences
                              ._productVariantsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$InventoryItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).productVariantsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.inventoryItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (inventoryBalancesRefs)
                        await $_getPrefetchedData<
                          InventoryItemRow,
                          $InventoryItemsTable,
                          InventoryBalanceRow
                        >(
                          currentTable: table,
                          referencedTable: $$InventoryItemsTableReferences
                              ._inventoryBalancesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$InventoryItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).inventoryBalancesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.inventoryItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (inventoryMovementsRefs)
                        await $_getPrefetchedData<
                          InventoryItemRow,
                          $InventoryItemsTable,
                          InventoryMovementRow
                        >(
                          currentTable: table,
                          referencedTable: $$InventoryItemsTableReferences
                              ._inventoryMovementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$InventoryItemsTableReferences(
                                db,
                                table,
                                p0,
                              ).inventoryMovementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.inventoryItemId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$InventoryItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InventoryItemsTable,
      InventoryItemRow,
      $$InventoryItemsTableFilterComposer,
      $$InventoryItemsTableOrderingComposer,
      $$InventoryItemsTableAnnotationComposer,
      $$InventoryItemsTableCreateCompanionBuilder,
      $$InventoryItemsTableUpdateCompanionBuilder,
      (InventoryItemRow, $$InventoryItemsTableReferences),
      InventoryItemRow,
      PrefetchHooks Function({
        bool defaultUnitId,
        bool productVariantsRefs,
        bool inventoryBalancesRefs,
        bool inventoryMovementsRefs,
      })
    >;
typedef $$ProductVariantsTableCreateCompanionBuilder =
    ProductVariantsCompanion Function({
      required String id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      required String productId,
      Value<String?> name,
      Value<String?> nameKey,
      required int salePriceMinor,
      Value<int?> standardCostMinor,
      Value<String?> inventoryItemId,
      required bool isDefault,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$ProductVariantsTableUpdateCompanionBuilder =
    ProductVariantsCompanion Function({
      Value<String> id,
      Value<bool> active,
      Value<int> version,
      Value<String?> createdEventId,
      Value<String?> lastEventId,
      Value<int?> lastServerSequence,
      Value<String> productId,
      Value<String?> name,
      Value<String?> nameKey,
      Value<int> salePriceMinor,
      Value<int?> standardCostMinor,
      Value<String?> inventoryItemId,
      Value<bool> isDefault,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$ProductVariantsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ProductVariantsTable,
          ProductVariantRow
        > {
  $$ProductVariantsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProductsTable _productIdTable(_$AppDatabase db) =>
      db.products.createAlias('product_variants__product_id__products__id');

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager(
      $_db,
      $_db.products,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $InventoryItemsTable _inventoryItemIdTable(_$AppDatabase db) => db
      .inventoryItems
      .createAlias('product_variants__inventory_item_id__inventory_items__id');

  $$InventoryItemsTableProcessedTableManager? get inventoryItemId {
    final $_column = $_itemColumn<String>('inventory_item_id');
    if ($_column == null) return null;
    final manager = $$InventoryItemsTableTableManager(
      $_db,
      $_db.inventoryItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_inventoryItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProductVariantsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableFilterComposer({
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

  ColumnFilters<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get salePriceMinor => $composableBuilder(
    column: $table.salePriceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get standardCostMinor => $composableBuilder(
    column: $table.standardCostMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableFilterComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryItemsTableFilterComposer get inventoryItemId {
    final $$InventoryItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductVariantsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableOrderingComposer({
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

  ColumnOrderings<String> get nameKey => $composableBuilder(
    column: $table.nameKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get salePriceMinor => $composableBuilder(
    column: $table.salePriceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get standardCostMinor => $composableBuilder(
    column: $table.standardCostMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableOrderingComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryItemsTableOrderingComposer get inventoryItemId {
    final $$InventoryItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableOrderingComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductVariantsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductVariantsTable> {
  $$ProductVariantsTableAnnotationComposer({
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

  GeneratedColumn<String> get nameKey =>
      $composableBuilder(column: $table.nameKey, builder: (column) => column);

  GeneratedColumn<int> get salePriceMinor => $composableBuilder(
    column: $table.salePriceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get standardCostMinor => $composableBuilder(
    column: $table.standardCostMinor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.productId,
      referencedTable: $db.products,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProductsTableAnnotationComposer(
            $db: $db,
            $table: $db.products,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryItemsTableAnnotationComposer get inventoryItemId {
    final $$InventoryItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProductVariantsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductVariantsTable,
          ProductVariantRow,
          $$ProductVariantsTableFilterComposer,
          $$ProductVariantsTableOrderingComposer,
          $$ProductVariantsTableAnnotationComposer,
          $$ProductVariantsTableCreateCompanionBuilder,
          $$ProductVariantsTableUpdateCompanionBuilder,
          (ProductVariantRow, $$ProductVariantsTableReferences),
          ProductVariantRow,
          PrefetchHooks Function({bool productId, bool inventoryItemId})
        > {
  $$ProductVariantsTableTableManager(
    _$AppDatabase db,
    $ProductVariantsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductVariantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductVariantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductVariantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> createdEventId = const Value.absent(),
                Value<String?> lastEventId = const Value.absent(),
                Value<int?> lastServerSequence = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> nameKey = const Value.absent(),
                Value<int> salePriceMinor = const Value.absent(),
                Value<int?> standardCostMinor = const Value.absent(),
                Value<String?> inventoryItemId = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductVariantsCompanion(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                productId: productId,
                name: name,
                nameKey: nameKey,
                salePriceMinor: salePriceMinor,
                standardCostMinor: standardCostMinor,
                inventoryItemId: inventoryItemId,
                isDefault: isDefault,
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
                required String productId,
                Value<String?> name = const Value.absent(),
                Value<String?> nameKey = const Value.absent(),
                required int salePriceMinor,
                Value<int?> standardCostMinor = const Value.absent(),
                Value<String?> inventoryItemId = const Value.absent(),
                required bool isDefault,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => ProductVariantsCompanion.insert(
                id: id,
                active: active,
                version: version,
                createdEventId: createdEventId,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                productId: productId,
                name: name,
                nameKey: nameKey,
                salePriceMinor: salePriceMinor,
                standardCostMinor: standardCostMinor,
                inventoryItemId: inventoryItemId,
                isDefault: isDefault,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ProductVariantsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({productId = false, inventoryItemId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (productId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.productId,
                                    referencedTable:
                                        $$ProductVariantsTableReferences
                                            ._productIdTable(db),
                                    referencedColumn:
                                        $$ProductVariantsTableReferences
                                            ._productIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (inventoryItemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.inventoryItemId,
                                    referencedTable:
                                        $$ProductVariantsTableReferences
                                            ._inventoryItemIdTable(db),
                                    referencedColumn:
                                        $$ProductVariantsTableReferences
                                            ._inventoryItemIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$ProductVariantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductVariantsTable,
      ProductVariantRow,
      $$ProductVariantsTableFilterComposer,
      $$ProductVariantsTableOrderingComposer,
      $$ProductVariantsTableAnnotationComposer,
      $$ProductVariantsTableCreateCompanionBuilder,
      $$ProductVariantsTableUpdateCompanionBuilder,
      (ProductVariantRow, $$ProductVariantsTableReferences),
      ProductVariantRow,
      PrefetchHooks Function({bool productId, bool inventoryItemId})
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
typedef $$InventoryBalancesTableCreateCompanionBuilder =
    InventoryBalancesCompanion Function({
      required String inventoryItemId,
      required int quantityOnHandAtomic,
      required int quantityAvailableAtomic,
      required String lastEventId,
      Value<int?> lastServerSequence,
      Value<int> rowid,
    });
typedef $$InventoryBalancesTableUpdateCompanionBuilder =
    InventoryBalancesCompanion Function({
      Value<String> inventoryItemId,
      Value<int> quantityOnHandAtomic,
      Value<int> quantityAvailableAtomic,
      Value<String> lastEventId,
      Value<int?> lastServerSequence,
      Value<int> rowid,
    });

final class $$InventoryBalancesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $InventoryBalancesTable,
          InventoryBalanceRow
        > {
  $$InventoryBalancesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $InventoryItemsTable _inventoryItemIdTable(_$AppDatabase db) =>
      db.inventoryItems.createAlias(
        'inventory_balances__inventory_item_id__inventory_items__id',
      );

  $$InventoryItemsTableProcessedTableManager get inventoryItemId {
    final $_column = $_itemColumn<String>('inventory_item_id')!;

    final manager = $$InventoryItemsTableTableManager(
      $_db,
      $_db.inventoryItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_inventoryItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$InventoryBalancesTableFilterComposer
    extends Composer<_$AppDatabase, $InventoryBalancesTable> {
  $$InventoryBalancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get quantityOnHandAtomic => $composableBuilder(
    column: $table.quantityOnHandAtomic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantityAvailableAtomic => $composableBuilder(
    column: $table.quantityAvailableAtomic,
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

  $$InventoryItemsTableFilterComposer get inventoryItemId {
    final $$InventoryItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryBalancesTableOrderingComposer
    extends Composer<_$AppDatabase, $InventoryBalancesTable> {
  $$InventoryBalancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get quantityOnHandAtomic => $composableBuilder(
    column: $table.quantityOnHandAtomic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantityAvailableAtomic => $composableBuilder(
    column: $table.quantityAvailableAtomic,
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

  $$InventoryItemsTableOrderingComposer get inventoryItemId {
    final $$InventoryItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableOrderingComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryBalancesTableAnnotationComposer
    extends Composer<_$AppDatabase, $InventoryBalancesTable> {
  $$InventoryBalancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get quantityOnHandAtomic => $composableBuilder(
    column: $table.quantityOnHandAtomic,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantityAvailableAtomic => $composableBuilder(
    column: $table.quantityAvailableAtomic,
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

  $$InventoryItemsTableAnnotationComposer get inventoryItemId {
    final $$InventoryItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryBalancesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InventoryBalancesTable,
          InventoryBalanceRow,
          $$InventoryBalancesTableFilterComposer,
          $$InventoryBalancesTableOrderingComposer,
          $$InventoryBalancesTableAnnotationComposer,
          $$InventoryBalancesTableCreateCompanionBuilder,
          $$InventoryBalancesTableUpdateCompanionBuilder,
          (InventoryBalanceRow, $$InventoryBalancesTableReferences),
          InventoryBalanceRow,
          PrefetchHooks Function({bool inventoryItemId})
        > {
  $$InventoryBalancesTableTableManager(
    _$AppDatabase db,
    $InventoryBalancesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryBalancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoryBalancesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoryBalancesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> inventoryItemId = const Value.absent(),
                Value<int> quantityOnHandAtomic = const Value.absent(),
                Value<int> quantityAvailableAtomic = const Value.absent(),
                Value<String> lastEventId = const Value.absent(),
                Value<int?> lastServerSequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryBalancesCompanion(
                inventoryItemId: inventoryItemId,
                quantityOnHandAtomic: quantityOnHandAtomic,
                quantityAvailableAtomic: quantityAvailableAtomic,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String inventoryItemId,
                required int quantityOnHandAtomic,
                required int quantityAvailableAtomic,
                required String lastEventId,
                Value<int?> lastServerSequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryBalancesCompanion.insert(
                inventoryItemId: inventoryItemId,
                quantityOnHandAtomic: quantityOnHandAtomic,
                quantityAvailableAtomic: quantityAvailableAtomic,
                lastEventId: lastEventId,
                lastServerSequence: lastServerSequence,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$InventoryBalancesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({inventoryItemId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (inventoryItemId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.inventoryItemId,
                                referencedTable:
                                    $$InventoryBalancesTableReferences
                                        ._inventoryItemIdTable(db),
                                referencedColumn:
                                    $$InventoryBalancesTableReferences
                                        ._inventoryItemIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$InventoryBalancesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InventoryBalancesTable,
      InventoryBalanceRow,
      $$InventoryBalancesTableFilterComposer,
      $$InventoryBalancesTableOrderingComposer,
      $$InventoryBalancesTableAnnotationComposer,
      $$InventoryBalancesTableCreateCompanionBuilder,
      $$InventoryBalancesTableUpdateCompanionBuilder,
      (InventoryBalanceRow, $$InventoryBalancesTableReferences),
      InventoryBalanceRow,
      PrefetchHooks Function({bool inventoryItemId})
    >;
typedef $$InventoryMovementsTableCreateCompanionBuilder =
    InventoryMovementsCompanion Function({
      required String movementId,
      required String inventoryItemId,
      Value<String?> saleItemId,
      required String eventId,
      Value<String?> reversalOfMovementId,
      required String movementType,
      required int quantityDeltaAtomic,
      Value<int?> totalCostMinor,
      required String reason,
      required DateTime createdAtLocal,
      Value<int?> serverSequence,
      Value<int> rowid,
    });
typedef $$InventoryMovementsTableUpdateCompanionBuilder =
    InventoryMovementsCompanion Function({
      Value<String> movementId,
      Value<String> inventoryItemId,
      Value<String?> saleItemId,
      Value<String> eventId,
      Value<String?> reversalOfMovementId,
      Value<String> movementType,
      Value<int> quantityDeltaAtomic,
      Value<int?> totalCostMinor,
      Value<String> reason,
      Value<DateTime> createdAtLocal,
      Value<int?> serverSequence,
      Value<int> rowid,
    });

final class $$InventoryMovementsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $InventoryMovementsTable,
          InventoryMovementRow
        > {
  $$InventoryMovementsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $InventoryItemsTable _inventoryItemIdTable(_$AppDatabase db) =>
      db.inventoryItems.createAlias(
        'inventory_movements__inventory_item_id__inventory_items__id',
      );

  $$InventoryItemsTableProcessedTableManager get inventoryItemId {
    final $_column = $_itemColumn<String>('inventory_item_id')!;

    final manager = $$InventoryItemsTableTableManager(
      $_db,
      $_db.inventoryItems,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_inventoryItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $InventoryMovementsTable _reversalOfMovementIdTable(
    _$AppDatabase db,
  ) => db.inventoryMovements.createAlias(
    'inventory_movements__reversal_of_movement_id__inventory_movements__movement_id',
  );

  $$InventoryMovementsTableProcessedTableManager? get reversalOfMovementId {
    final $_column = $_itemColumn<String>('reversal_of_movement_id');
    if ($_column == null) return null;
    final manager = $$InventoryMovementsTableTableManager(
      $_db,
      $_db.inventoryMovements,
    ).filter((f) => f.movementId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _reversalOfMovementIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$InventoryMovementsTableFilterComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get movementId => $composableBuilder(
    column: $table.movementId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get saleItemId => $composableBuilder(
    column: $table.saleItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get movementType => $composableBuilder(
    column: $table.movementType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantityDeltaAtomic => $composableBuilder(
    column: $table.quantityDeltaAtomic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalCostMinor => $composableBuilder(
    column: $table.totalCostMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtLocal => $composableBuilder(
    column: $table.createdAtLocal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => ColumnFilters(column),
  );

  $$InventoryItemsTableFilterComposer get inventoryItemId {
    final $$InventoryItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableFilterComposer get reversalOfMovementId {
    final $$InventoryMovementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reversalOfMovementId,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.movementId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableFilterComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryMovementsTableOrderingComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get movementId => $composableBuilder(
    column: $table.movementId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saleItemId => $composableBuilder(
    column: $table.saleItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get movementType => $composableBuilder(
    column: $table.movementType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantityDeltaAtomic => $composableBuilder(
    column: $table.quantityDeltaAtomic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalCostMinor => $composableBuilder(
    column: $table.totalCostMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtLocal => $composableBuilder(
    column: $table.createdAtLocal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => ColumnOrderings(column),
  );

  $$InventoryItemsTableOrderingComposer get inventoryItemId {
    final $$InventoryItemsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableOrderingComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableOrderingComposer get reversalOfMovementId {
    final $$InventoryMovementsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.reversalOfMovementId,
      referencedTable: $db.inventoryMovements,
      getReferencedColumn: (t) => t.movementId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryMovementsTableOrderingComposer(
            $db: $db,
            $table: $db.inventoryMovements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$InventoryMovementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $InventoryMovementsTable> {
  $$InventoryMovementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get movementId => $composableBuilder(
    column: $table.movementId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get saleItemId => $composableBuilder(
    column: $table.saleItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get movementType => $composableBuilder(
    column: $table.movementType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantityDeltaAtomic => $composableBuilder(
    column: $table.quantityDeltaAtomic,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalCostMinor => $composableBuilder(
    column: $table.totalCostMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAtLocal => $composableBuilder(
    column: $table.createdAtLocal,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverSequence => $composableBuilder(
    column: $table.serverSequence,
    builder: (column) => column,
  );

  $$InventoryItemsTableAnnotationComposer get inventoryItemId {
    final $$InventoryItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.inventoryItemId,
      referencedTable: $db.inventoryItems,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$InventoryItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.inventoryItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$InventoryMovementsTableAnnotationComposer get reversalOfMovementId {
    final $$InventoryMovementsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.reversalOfMovementId,
          referencedTable: $db.inventoryMovements,
          getReferencedColumn: (t) => t.movementId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$InventoryMovementsTableAnnotationComposer(
                $db: $db,
                $table: $db.inventoryMovements,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$InventoryMovementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InventoryMovementsTable,
          InventoryMovementRow,
          $$InventoryMovementsTableFilterComposer,
          $$InventoryMovementsTableOrderingComposer,
          $$InventoryMovementsTableAnnotationComposer,
          $$InventoryMovementsTableCreateCompanionBuilder,
          $$InventoryMovementsTableUpdateCompanionBuilder,
          (InventoryMovementRow, $$InventoryMovementsTableReferences),
          InventoryMovementRow,
          PrefetchHooks Function({
            bool inventoryItemId,
            bool reversalOfMovementId,
          })
        > {
  $$InventoryMovementsTableTableManager(
    _$AppDatabase db,
    $InventoryMovementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoryMovementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoryMovementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoryMovementsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> movementId = const Value.absent(),
                Value<String> inventoryItemId = const Value.absent(),
                Value<String?> saleItemId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String?> reversalOfMovementId = const Value.absent(),
                Value<String> movementType = const Value.absent(),
                Value<int> quantityDeltaAtomic = const Value.absent(),
                Value<int?> totalCostMinor = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<DateTime> createdAtLocal = const Value.absent(),
                Value<int?> serverSequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryMovementsCompanion(
                movementId: movementId,
                inventoryItemId: inventoryItemId,
                saleItemId: saleItemId,
                eventId: eventId,
                reversalOfMovementId: reversalOfMovementId,
                movementType: movementType,
                quantityDeltaAtomic: quantityDeltaAtomic,
                totalCostMinor: totalCostMinor,
                reason: reason,
                createdAtLocal: createdAtLocal,
                serverSequence: serverSequence,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String movementId,
                required String inventoryItemId,
                Value<String?> saleItemId = const Value.absent(),
                required String eventId,
                Value<String?> reversalOfMovementId = const Value.absent(),
                required String movementType,
                required int quantityDeltaAtomic,
                Value<int?> totalCostMinor = const Value.absent(),
                required String reason,
                required DateTime createdAtLocal,
                Value<int?> serverSequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoryMovementsCompanion.insert(
                movementId: movementId,
                inventoryItemId: inventoryItemId,
                saleItemId: saleItemId,
                eventId: eventId,
                reversalOfMovementId: reversalOfMovementId,
                movementType: movementType,
                quantityDeltaAtomic: quantityDeltaAtomic,
                totalCostMinor: totalCostMinor,
                reason: reason,
                createdAtLocal: createdAtLocal,
                serverSequence: serverSequence,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$InventoryMovementsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({inventoryItemId = false, reversalOfMovementId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (inventoryItemId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.inventoryItemId,
                                    referencedTable:
                                        $$InventoryMovementsTableReferences
                                            ._inventoryItemIdTable(db),
                                    referencedColumn:
                                        $$InventoryMovementsTableReferences
                                            ._inventoryItemIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (reversalOfMovementId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.reversalOfMovementId,
                                    referencedTable:
                                        $$InventoryMovementsTableReferences
                                            ._reversalOfMovementIdTable(db),
                                    referencedColumn:
                                        $$InventoryMovementsTableReferences
                                            ._reversalOfMovementIdTable(db)
                                            .movementId,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$InventoryMovementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InventoryMovementsTable,
      InventoryMovementRow,
      $$InventoryMovementsTableFilterComposer,
      $$InventoryMovementsTableOrderingComposer,
      $$InventoryMovementsTableAnnotationComposer,
      $$InventoryMovementsTableCreateCompanionBuilder,
      $$InventoryMovementsTableUpdateCompanionBuilder,
      (InventoryMovementRow, $$InventoryMovementsTableReferences),
      InventoryMovementRow,
      PrefetchHooks Function({bool inventoryItemId, bool reversalOfMovementId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$InventoryItemsTableTableManager get inventoryItems =>
      $$InventoryItemsTableTableManager(_db, _db.inventoryItems);
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(_db, _db.productVariants);
  $$EspaciosTableTableManager get espacios =>
      $$EspaciosTableTableManager(_db, _db.espacios);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$EventRefsTableTableManager get eventRefs =>
      $$EventRefsTableTableManager(_db, _db.eventRefs);
  $$SyncCheckpointsTableTableManager get syncCheckpoints =>
      $$SyncCheckpointsTableTableManager(_db, _db.syncCheckpoints);
  $$InventoryBalancesTableTableManager get inventoryBalances =>
      $$InventoryBalancesTableTableManager(_db, _db.inventoryBalances);
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(_db, _db.inventoryMovements);
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

mixin _$ProductoDaoMixin on DatabaseAccessor<AppDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $UnitsTable get units => attachedDatabase.units;
  $ProductsTable get products => attachedDatabase.products;
  $InventoryItemsTable get inventoryItems => attachedDatabase.inventoryItems;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  ProductoDaoManager get managers => ProductoDaoManager(this);
}

class ProductoDaoManager {
  final _$ProductoDaoMixin _db;
  ProductoDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$InventoryItemsTableTableManager get inventoryItems =>
      $$InventoryItemsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryItems,
      );
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(
        _db.attachedDatabase,
        _db.productVariants,
      );
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

mixin _$UnitDaoMixin on DatabaseAccessor<AppDatabase> {
  $UnitsTable get units => attachedDatabase.units;
  UnitDaoManager get managers => UnitDaoManager(this);
}

class UnitDaoManager {
  final _$UnitDaoMixin _db;
  UnitDaoManager(this._db);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
}

mixin _$InventoryDaoMixin on DatabaseAccessor<AppDatabase> {
  $UnitsTable get units => attachedDatabase.units;
  $InventoryItemsTable get inventoryItems => attachedDatabase.inventoryItems;
  $InventoryBalancesTable get inventoryBalances =>
      attachedDatabase.inventoryBalances;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  InventoryDaoManager get managers => InventoryDaoManager(this);
}

class InventoryDaoManager {
  final _$InventoryDaoMixin _db;
  InventoryDaoManager(this._db);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$InventoryItemsTableTableManager get inventoryItems =>
      $$InventoryItemsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryItems,
      );
  $$InventoryBalancesTableTableManager get inventoryBalances =>
      $$InventoryBalancesTableTableManager(
        _db.attachedDatabase,
        _db.inventoryBalances,
      );
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryMovements,
      );
}
