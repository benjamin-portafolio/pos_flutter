// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
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
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
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
    syncStatus,
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
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
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
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
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

  /// Synchronization status: 'pending', 'synced', 'rejected', 'conflict'
  final String syncStatus;
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
    required this.syncStatus,
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
    map['sync_status'] = Variable<String>(syncStatus);
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
      syncStatus: Value(syncStatus),
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
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
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
      'syncStatus': serializer.toJson<String>(syncStatus),
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
    String? syncStatus,
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
    syncStatus: syncStatus ?? this.syncStatus,
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
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
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
          ..write('syncStatus: $syncStatus')
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
    syncStatus,
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
          other.syncStatus == this.syncStatus);
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
  final Value<String> syncStatus;
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
    this.syncStatus = const Value.absent(),
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
    this.syncStatus = const Value.absent(),
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
    Expression<String>? syncStatus,
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
      if (syncStatus != null) 'sync_status': syncStatus,
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
    Value<String>? syncStatus,
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
      syncStatus: syncStatus ?? this.syncStatus,
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
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
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
          ..write('syncStatus: $syncStatus')
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

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $EspaciosTable espacios = $EspaciosTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $EventRefsTable eventRefs = $EventRefsTable(this);
  late final EspacioDao espacioDao = EspacioDao(this as AppDatabase);
  late final EventDao eventDao = EventDao(this as AppDatabase);
  late final EventRefDao eventRefDao = EventRefDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    espacios,
    events,
    eventRefs,
  ];
}

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
      Value<String> syncStatus,
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
      Value<String> syncStatus,
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

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
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

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
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

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
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
                Value<String> syncStatus = const Value.absent(),
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
                syncStatus: syncStatus,
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
                Value<String> syncStatus = const Value.absent(),
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
                syncStatus: syncStatus,
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

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$EspaciosTableTableManager get espacios =>
      $$EspaciosTableTableManager(_db, _db.espacios);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$EventRefsTableTableManager get eventRefs =>
      $$EventRefsTableTableManager(_db, _db.eventRefs);
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
