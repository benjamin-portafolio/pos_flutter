import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/pending_event_revalidator.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_preflight_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late EspacioDao espacioDao;
  late EventDao eventDao;
  late EventRefDao eventRefDao;
  late SyncCheckpointDao checkpointDao;
  late DriftSyncPersistence syncPersistence;
  late DriftCategoriaProjectionStore categoriaProjectionStore;
  late DriftEspacioProjectionStore espacioProjectionStore;
  late DriftLocalEventStore localEventStore;
  late RemoteEventApplier remoteEventApplier;
  late PendingEventRevalidator pendingEventRevalidator;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    espacioDao = EspacioDao(db);
    eventDao = EventDao(db);
    eventRefDao = EventRefDao(db);
    checkpointDao = SyncCheckpointDao(db);
    syncPersistence = DriftSyncPersistence(
      eventDao: eventDao,
      eventRefDao: eventRefDao,
      syncCheckpointDao: checkpointDao,
    );
    espacioProjectionStore = DriftEspacioProjectionStore(
      espacioDao: espacioDao,
    );
    categoriaProjectionStore = DriftCategoriaProjectionStore(
      categoriaDao: categoriaDao,
    );
    final eventProcessor = EventProcessor(
      handlers: {
        ...espacioEventHandlers(EspacioEventHandler(espacioProjectionStore)),
        ...categoriaEventHandlers(
          CategoriaEventHandler(categoriaProjectionStore),
        ),
      },
    );
    localEventStore = DriftLocalEventStore(
      db: db,
      eventDao: eventDao,
      eventRefDao: eventRefDao,
      eventProcessor: eventProcessor,
    );
    remoteEventApplier = RemoteEventApplier(
      eventStore: DriftSyncedEventStore(db: db),
      eventProcessor: eventProcessor,
      serverEchoAcknowledger: ServerEchoAcknowledger(
        categoriaProjectionStore: categoriaProjectionStore,
      ),
    );
    pendingEventRevalidator = PendingEventRevalidator(
      syncPersistence: syncPersistence,
      syncedEventHistory: syncPersistence,
      espacioProjectionStore: espacioProjectionStore,
      categoriaProjectionStore: categoriaProjectionStore,
      categoriaConflictProjectionRestorer: CategoriaConflictProjectionRestorer(
        categoriaProjectionStore,
      ),
      categoriaMovidaConflictProjectionRestorer:
          CategoriaMovidaConflictProjectionRestorer(categoriaProjectionStore),
    );
  });

  tearDown(() async {
    await db.close();
  });

  SyncPreflightService buildPreflightService({required http.Client client}) {
    return SyncPreflightService(
      syncPersistence: syncPersistence,
      endpointConfig: SyncEndpointConfig(
        initialBaseUrl: 'http://localhost:3000',
      ),
      commandContext: const LocalCommandContext(
        deviceId: 'device_tablet_01',
        userId: 'user_01',
      ),
      remoteEventApplier: remoteEventApplier,
      pendingEventRevalidator: pendingEventRevalidator,
      client: client,
    );
  }

  test('omite preflight cuando los pendientes solo declaran affects', () async {
    await localEventStore.appendAndApply(
      _localEspacioEvent(
        eventId: 'local_event_1',
        aggregateId: 'local_space_1',
        identificacion: null,
      ),
      refs: const [
        LocalEventRef.affects(refType: 'espacio', refId: 'local_space_1'),
      ],
    );

    final service = buildPreflightService(
      client: MockClient((_) async {
        throw StateError('No debe llamar /sync/preflight.');
      }),
    );

    final report = await service.preflightPendingEvents();

    expect(report.skipped, isTrue);
    expect(report.reason, 'not_required');
  });

  test(
    'omite request remoto si full pull ya cubre la ultima secuencia',
    () async {
      await localEventStore.appendAndApply(
        _localEspacioEvent(
          eventId: 'local_event_1',
          aggregateId: 'local_space_1',
          identificacion: 'terraza',
        ),
        refs: const [
          LocalEventRef.affects(refType: 'espacio', refId: 'local_space_1'),
          LocalEventRef.requiresUnique(
            refType: 'espacio_identificacion',
            refId: 'terraza',
          ),
        ],
      );
      await remoteEventApplier.applySyncedEvents([
        SyncEvent.fromJson(
          _remoteEspacioEvent(
            eventId: 'remote_event_1',
            aggregateId: 'remote_space_1',
            serverSequence: 10,
            identificacion: 'terraza',
          ),
        ),
      ]);
      await checkpointDao.actualizarLastFullPullServerSequence(10);

      final service = buildPreflightService(
        client: MockClient((_) async {
          throw StateError('No debe llamar /sync/preflight.');
        }),
      );

      final report = await service.preflightPendingEvents(
        latestServerSequence: 10,
      );
      final events = await db.select(db.events).get();

      expect(report.skipped, isTrue);
      expect(report.reason, 'server_sequence_current');
      expect(report.localConflicts, 1);
      expect(
        events
            .singleWhere((event) => event.eventId == 'local_event_1')
            .deliveryStatus,
        'conflict',
      );
    },
  );

  test('aplica evento remoto impactante y marca conflicto local', () async {
    await localEventStore.appendAndApply(
      _localEspacioEvent(
        eventId: 'local_event_1',
        aggregateId: 'local_space_1',
        identificacion: 'terraza',
      ),
      refs: const [
        LocalEventRef.affects(refType: 'espacio', refId: 'local_space_1'),
        LocalEventRef.requiresUnique(
          refType: 'espacio_identificacion',
          refId: 'terraza',
        ),
      ],
    );

    final service = buildPreflightService(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/sync/preflight');

        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['device_id'], 'device_tablet_01');
        expect(body['last_full_pull_server_sequence'], 0);

        final pendingRefs = body['pending_refs'] as List;
        final firstPendingRef = pendingRefs.single as Map<String, Object?>;
        final refs = firstPendingRef['refs'] as List;
        expect(
          refs.cast<Map>().map((ref) => ref['type']),
          contains('espacio_identificacion'),
        );

        return http.Response(
          jsonEncode({
            'events': [
              _remoteEspacioEvent(
                eventId: 'remote_event_1',
                aggregateId: 'remote_space_1',
                serverSequence: 9,
                identificacion: 'terraza',
              ),
            ],
            'preflight_sequence': 10,
            'has_more': false,
            'requires_full_pull_before_push': false,
            'reason': null,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final report = await service.preflightPendingEvents();
    final events = await db.select(db.events).get();
    final espacios = await espacioDao.obtenerEspacios();
    final lastPreflight = await checkpointDao
        .obtenerLastPreflightServerSequence();

    expect(report.localConflicts, 1);
    expect(report.impactingEvents, 1);
    expect(lastPreflight, 10);
    expect(
      events
          .singleWhere((event) => event.eventId == 'local_event_1')
          .deliveryStatus,
      'conflict',
    );
    expect(
      events
          .singleWhere((event) => event.eventId == 'remote_event_1')
          .deliveryStatus,
      'delivered',
    );
    expect(espacios, hasLength(1));
    expect(espacios.single.id, 'remote_space_1');
  });

  test(
    'categoria_actualizada entra en conflicto si preflight cambió el mismo campo',
    () async {
      await remoteEventApplier.applySyncedEvents([
        SyncEvent.fromJson(
          _remoteCategoriaCreada(
            eventId: 'remote_category_created',
            serverSequence: 5,
          ),
        ),
      ]);
      await checkpointDao.actualizarLastFullPullServerSequence(5);
      await localEventStore.appendAndApply(
        _localCategoriaActualizada(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );

      final service = buildPreflightService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final pendingRef =
              (body['pending_refs'] as List).single as Map<String, Object?>;
          expect(pendingRef['changed_fields'], ['name']);

          return http.Response(
            jsonEncode({
              'events': [
                _remoteCategoriaActualizada(
                  eventId: 'remote_category_updated',
                  serverSequence: 6,
                ),
              ],
              'preflight_sequence': 6,
              'has_more': false,
              'requires_full_pull_before_push': false,
              'reason': null,
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final report = await service.preflightPendingEvents();
      final category = await categoriaDao.obtenerCategoriaPorId('category_1');
      final localEvent = (await db.select(db.events).get()).singleWhere(
        (event) => event.eventId == 'local_category_updated',
      );

      expect(report.localConflicts, 1);
      expect(localEvent.deliveryStatus, 'conflict');
      expect(localEvent.rejectionReason, contains('name'));
      expect(category!.name, 'Bebidas del servidor');
      expect(category.lastEventId, 'remote_category_updated');
      expect(category.lastServerSequence, 6);
    },
  );

  test(
    'categoria_movida conserva el orden oficial si preflight reordenó la lista',
    () async {
      await remoteEventApplier.applySyncedEvents([
        SyncEvent.fromJson(
          _remoteCategoriaCreada(
            eventId: 'remote_category_1_created',
            aggregateId: 'category_1',
            serverSequence: 5,
            sortOrder: 0,
          ),
        ),
        SyncEvent.fromJson(
          _remoteCategoriaCreada(
            eventId: 'remote_category_2_created',
            aggregateId: 'category_2',
            serverSequence: 6,
            sortOrder: 1,
          ),
        ),
      ]);
      await checkpointDao.actualizarLastFullPullServerSequence(6);
      await localEventStore.appendAndApply(
        _localCategoriaMovida(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
        ],
      );

      final service = buildPreflightService(
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'events': [_remoteCategoriaMovida()],
              'preflight_sequence': 7,
              'has_more': false,
              'requires_full_pull_before_push': false,
              'reason': null,
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final report = await service.preflightPendingEvents();
      final categories = await categoriaDao.obtenerCategorias();
      final localEvent = (await db.select(db.events).get()).singleWhere(
        (event) => event.eventId == 'local_category_moved',
      );

      expect(report.localConflicts, 1);
      expect(localEvent.deliveryStatus, 'conflict');
      expect(categories.map((category) => category.id), [
        'category_2',
        'category_1',
      ]);
      expect(categories.map((category) => category.lastEventId).toSet(), {
        'remote_category_moved',
      });
    },
  );

  test(
    'movimiento B conserva pending cuando su base local A ya fue entregada',
    () async {
      await remoteEventApplier.applySyncedEvents([
        SyncEvent.fromJson(
          _remoteCategoriaCreada(
            eventId: 'remote_category_1_created',
            aggregateId: 'category_1',
            serverSequence: 5,
            sortOrder: 0,
          ),
        ),
        SyncEvent.fromJson(
          _remoteCategoriaCreada(
            eventId: 'remote_category_2_created',
            aggregateId: 'category_2',
            serverSequence: 6,
            sortOrder: 1,
          ),
        ),
      ]);

      final movementA = _localCategoriaMovidaA();
      final movementB = _localCategoriaMovidaB();
      for (final event in [movementA, movementB]) {
        await localEventStore.appendAndApply(
          event,
          refs: const [
            LocalEventRef.affects(refType: 'category', refId: 'category_1'),
            LocalEventRef.affects(refType: 'category', refId: 'category_2'),
          ],
        );
      }

      final waitingReport = await pendingEventRevalidator
          .revalidatePendingEvents();
      var events = await db.select(db.events).get();
      expect(waitingReport.checked, 2);
      expect(waitingReport.conflicts, 0);
      expect(
        events
            .where(
              (event) =>
                  event.eventId == movementA.eventId ||
                  event.eventId == movementB.eventId,
            )
            .map((event) => event.deliveryStatus)
            .toSet(),
        {'pending'},
      );

      await remoteEventApplier.applySyncedEvents([
        movementA.copyWith(
          serverSequence: 7,
          createdAtServer: DateTime.utc(2026, 6, 9, 20, 33),
          deliveryStatus: 'delivered',
        ),
      ]);

      final report = await pendingEventRevalidator.revalidatePendingEvents();
      events = await db.select(db.events).get();
      final categories = await categoriaDao.obtenerCategorias();

      expect(report.checked, 1);
      expect(report.conflicts, 0);
      expect(
        events
            .singleWhere((event) => event.eventId == movementA.eventId)
            .deliveryStatus,
        'delivered',
      );
      expect(
        events
            .singleWhere((event) => event.eventId == movementB.eventId)
            .deliveryStatus,
        'pending',
      );
      expect(categories.map((category) => category.id), [
        'category_1',
        'category_2',
      ]);
      expect(categories.map((category) => category.sortOrder), [0, 1]);
      expect(categories.map((category) => category.lastEventId).toSet(), {
        movementB.eventId,
      });
      expect(
        categories.map((category) => category.lastServerSequence).toSet(),
        {7},
      );
    },
  );
}

SyncEvent _localEspacioEvent({
  required String eventId,
  required String aggregateId,
  required String? identificacion,
}) {
  return SyncEvent(
    eventId: eventId,
    aggregateType: 'espacio',
    aggregateId: aggregateId,
    eventType: 'espacio_creado',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.parse('2026-06-09T20:30:00.000Z'),
    baseVersion: 1,
    payload: {
      'nombre': 'Terraza',
      'identificacion': identificacion,
      'visibilidad': 'sin_restriccion',
    },
  );
}

Map<String, Object?> _remoteEspacioEvent({
  required String eventId,
  required String aggregateId,
  required int serverSequence,
  required String? identificacion,
}) {
  return {
    'event_id': eventId,
    'aggregate_type': 'espacio',
    'aggregate_id': aggregateId,
    'event_type': 'espacio_creado',
    'device_id': 'device_tablet_02',
    'user_id': 'user_02',
    'local_sequence': 1,
    'server_sequence': serverSequence,
    'base_server_sequence': null,
    'base_version': 1,
    'created_at_local': '2026-06-09T20:30:00.000Z',
    'created_at_server': '2026-06-09T20:31:00.000Z',
    'payload': {
      'nombre': 'Terraza servidor',
      'identificacion': identificacion,
      'visibilidad': 'sin_restriccion',
    },
    'sync_status': 'synced',
  };
}

SyncEvent _localCategoriaActualizada() {
  return SyncEvent(
    eventId: 'local_category_updated',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_actualizada',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    baseServerSequence: 5,
    baseVersion: 1,
    createdAtLocal: DateTime.parse('2026-06-09T20:32:00.000Z'),
    payload: const {
      'base_event_id': 'remote_category_created',
      'changed_fields': ['name'],
      'changes': {
        'name': {'from': 'Bebidas', 'to': 'Bebidas locales'},
      },
    },
  );
}

SyncEvent _localCategoriaMovida() {
  return SyncEvent(
    eventId: 'local_category_moved',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_movida',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    baseServerSequence: 5,
    baseVersion: 1,
    createdAtLocal: DateTime.parse('2026-06-09T20:32:00.000Z'),
    payload: const {
      'base_event_id': 'remote_category_1_created',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 0, 'to': 1},
      },
      'displaced_category': {
        'category_id': 'category_2',
        'base_event_id': 'remote_category_2_created',
        'base_version': 1,
        'base_server_sequence': 6,
        'sort_order': {'from': 1, 'to': 0},
      },
    },
  );
}

SyncEvent _localCategoriaMovidaA() {
  return SyncEvent(
    eventId: 'local_movement_a',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_movida',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    baseServerSequence: 5,
    baseVersion: 1,
    createdAtLocal: DateTime.utc(2026, 6, 9, 20, 32),
    payload: const {
      'base_event_id': 'remote_category_1_created',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 0, 'to': 1},
      },
      'displaced_category': {
        'category_id': 'category_2',
        'base_event_id': 'remote_category_2_created',
        'base_version': 1,
        'base_server_sequence': 6,
        'sort_order': {'from': 1, 'to': 0},
      },
    },
  );
}

SyncEvent _localCategoriaMovidaB() {
  return SyncEvent(
    eventId: 'local_movement_b',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_movida',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    baseServerSequence: 5,
    baseVersion: 2,
    createdAtLocal: DateTime.utc(2026, 6, 9, 20, 32, 1),
    payload: const {
      'base_event_id': 'local_movement_a',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 1, 'to': 0},
      },
      'displaced_category': {
        'category_id': 'category_2',
        'base_event_id': 'local_movement_a',
        'base_version': 2,
        'base_server_sequence': 6,
        'sort_order': {'from': 0, 'to': 1},
      },
    },
  );
}

Map<String, Object?> _remoteCategoriaCreada({
  required String eventId,
  String aggregateId = 'category_1',
  required int serverSequence,
  int sortOrder = 0,
}) {
  return {
    'event_id': eventId,
    'aggregate_type': 'category',
    'aggregate_id': aggregateId,
    'event_type': 'categoria_creada',
    'device_id': 'other_device',
    'user_id': 'user_02',
    'local_sequence': 1,
    'server_sequence': serverSequence,
    'base_server_sequence': null,
    'base_version': 1,
    'created_at_local': '2026-06-09T20:30:00.000Z',
    'created_at_server': '2026-06-09T20:31:00.000Z',
    'payload': {
      'name': 'Bebidas',
      'color_key': 'cyan',
      'sort_order': sortOrder,
    },
    'sync_status': 'synced',
  };
}

Map<String, Object?> _remoteCategoriaMovida() {
  return {
    'event_id': 'remote_category_moved',
    'aggregate_type': 'category',
    'aggregate_id': 'category_1',
    'event_type': 'categoria_movida',
    'device_id': 'other_device',
    'user_id': 'user_02',
    'local_sequence': 3,
    'server_sequence': 7,
    'base_server_sequence': 5,
    'base_version': 1,
    'created_at_local': '2026-06-09T20:33:00.000Z',
    'created_at_server': '2026-06-09T20:34:00.000Z',
    'payload': {
      'base_event_id': 'remote_category_1_created',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 0, 'to': 1},
      },
      'displaced_category': {
        'category_id': 'category_2',
        'base_event_id': 'remote_category_2_created',
        'base_version': 1,
        'base_server_sequence': 6,
        'sort_order': {'from': 1, 'to': 0},
      },
    },
    'sync_status': 'synced',
  };
}

Map<String, Object?> _remoteCategoriaActualizada({
  required String eventId,
  required int serverSequence,
}) {
  return {
    'event_id': eventId,
    'aggregate_type': 'category',
    'aggregate_id': 'category_1',
    'event_type': 'categoria_actualizada',
    'device_id': 'other_device',
    'user_id': 'user_02',
    'local_sequence': 2,
    'server_sequence': serverSequence,
    'base_server_sequence': 5,
    'base_version': 1,
    'created_at_local': '2026-06-09T20:33:00.000Z',
    'created_at_server': '2026-06-09T20:34:00.000Z',
    'payload': {
      'base_event_id': 'remote_category_created',
      'changed_fields': ['name'],
      'changes': {
        'name': {'from': 'Bebidas', 'to': 'Bebidas del servidor'},
      },
    },
    'sync_status': 'synced',
  };
}
