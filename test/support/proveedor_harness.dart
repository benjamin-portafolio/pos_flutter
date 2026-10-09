import 'dart:convert';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/proveedores/proveedor_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/proveedor_creado_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/proveedor_actualizado_event_handler.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_actualizado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_proveedor_projection_store.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';

/// SQLite aislado. El fallo inyectado ocurre después de escribir la proyección.
class ProveedorHarness {
  ProveedorHarness({AppDatabase? database, AppMode mode = AppMode.standalone})
    : db = database ?? AppDatabase.forTesting(NativeDatabase.memory()),
      config = AppConfigController(AppConfig.initial.copyWith(mode: mode));

  final AppDatabase db;
  final AppConfigController config;
  bool failAfterApply = false;
  final appends = <LocalEventAppend>[];
  late final projection = DriftProveedorProjectionStore(db.proveedorDao);
  late final repository = ProveedorRepositoryImpl(db.proveedorDao);
  late final created = ProveedorCreadoEventHandler(projection);
  late final updated = ProveedorActualizadoEventHandler(projection);
  late final processor = EventProcessor(
    handlers: {
      ProveedorCreadoPayload.eventType: (event) async {
        await created.apply(event);
        if (failAfterApply) {
          throw StateError('fallo inyectado después del alta');
        }
      },
      ProveedorActualizadoPayload.eventType: (event) async {
        await updated.apply(event);
        if (failAfterApply) {
          throw StateError('fallo inyectado después de editar');
        }
      },
    },
  );
  late final local = DriftLocalEventStore(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    eventProcessor: processor,
    appConfigController: config,
  );
  late final service = ProveedorCommandService(
    eventStore: _RecordingEvents(local, appends),
    projectionStore: projection,
    config: config,
    history: DriftSyncPersistence(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      syncCheckpointDao: db.syncCheckpointDao,
    ),
    commandContext: const LocalCommandContext(
      deviceId: 'supplier-tablet',
      userId: 'supplier-user',
    ),
  );

  Future<List<SyncEvent>> events() async => [
    for (final row in await (db.select(
      db.events,
    )..orderBy([(t) => OrderingTerm(expression: t.localSequence)])).get())
      SyncEvent(
        eventId: row.eventId,
        aggregateType: row.aggregateType,
        aggregateId: row.aggregateId,
        eventType: row.eventType,
        deviceId: row.deviceId,
        userId: row.userId,
        baseVersion: row.baseVersion,
        baseServerSequence: row.baseServerSequence,
        createdAtLocal: row.createdAtLocal,
        deliveryStatus: row.deliveryStatus,
        payload: Map<String, Object?>.from(jsonDecode(row.payload) as Map),
      ),
  ];

  Future<void> dispose() async {
    await config.dispose();
    await db.close();
  }
}

class _RecordingEvents implements LocalEventStore {
  _RecordingEvents(this.delegate, this.appends);
  final LocalEventStore delegate;
  final List<LocalEventAppend> appends;
  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) {
    appends.add(LocalEventAppend(event: event, refs: refs));
    return delegate.appendAndApply(event, refs: refs);
  }
}
