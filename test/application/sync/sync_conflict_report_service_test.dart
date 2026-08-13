import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/sync_conflict_report_service.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';

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

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    espacioDao = EspacioDao(db);
    eventDao = EventDao(db);
    eventRefDao = EventRefDao(db);
    checkpointDao = SyncCheckpointDao(db);
    syncPersistence = DriftSyncPersistence(
      db: db,
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
    localEventStore = DriftLocalEventStore(
      db: db,
      eventDao: eventDao,
      eventRefDao: eventRefDao,
      eventProcessor: EventProcessor(
        handlers: {
          ...espacioEventHandlers(EspacioEventHandler(espacioProjectionStore)),
          ...categoriaEventHandlers(
            CategoriaEventHandler(categoriaProjectionStore),
          ),
        },
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('reporta conflicto local y conserva delivery_status conflict', () async {
    await localEventStore.appendAndApply(
      _localEspacioEvent(),
      refs: const [
        LocalEventRef.affects(refType: 'espacio', refId: 'local_space_1'),
        LocalEventRef.requiresUnique(
          refType: 'espacio_identificacion',
          refId: 'terraza',
        ),
      ],
    );
    await syncPersistence.updateEventSyncStatus(
      'local_event_1',
      'conflict',
      rejectionReason:
          'Ya existe un espacio oficial con identificacion terraza.',
    );
    await espacioProjectionStore.deleteCreatedByEvent('local_event_1');

    final service = SyncConflictReportService(
      syncPersistence: syncPersistence,
      endpointConfig: SyncEndpointConfig(
        initialBaseUrl: 'http://localhost:3000',
      ),
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/sync/conflicts/report');

        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['device_id'], 'device_tablet_01');

        final events = body['events'] as List;
        final event = events.single as Map<String, Object?>;
        expect(event['event_id'], 'local_event_1');
        expect(event['reason'], contains('identificacion terraza'));

        final refs = event['refs'] as List;
        expect(
          refs.cast<Map>().map((ref) => ref['type']),
          containsAll(['espacio', 'espacio_identificacion']),
        );

        return http.Response(
          jsonEncode({
            'results': [
              {
                'event_id': 'local_event_1',
                'status': 'conflict',
                'server_sequence': 12,
                'created_at_server': '2026-06-09T20:31:00.000Z',
                'reason':
                    'Ya existe un espacio oficial con identificacion terraza.',
              },
            ],
            'server_time': '2026-06-09T20:31:00.000Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final report = await service.reportLocalConflicts();
    final event = (await db.select(db.events).get()).single;
    final refs = await db.select(db.eventRefs).get();
    final espacios = await espacioDao.obtenerEspacios();

    expect(report.total, 1);
    expect(report.conflicts, 1);
    expect(event.deliveryStatus, 'conflict');
    expect(event.serverSequence, 12);
    expect(event.createdAtServer, isNotNull);
    expect(refs.map((ref) => ref.source).toSet(), {'server'});
    expect(refs.map((ref) => ref.serverSequence).toSet(), {12});
    expect(espacios, isEmpty);
  });

  test(
    'reportar conflictos encadenados no restaura la proyección otra vez',
    () async {
      final created1 = _localCategoriaCreada(
        eventId: 'category_1_created',
        categoryId: 'category_1',
        name: 'Uno',
        sortOrder: 0,
      );
      final created2 = _localCategoriaCreada(
        eventId: 'category_2_created',
        categoryId: 'category_2',
        name: 'Dos',
        sortOrder: 1,
      );
      for (final entry in [(created1, 5), (created2, 6)]) {
        await localEventStore.appendAndApply(
          entry.$1,
          refs: [
            LocalEventRef.affects(
              refType: 'category',
              refId: entry.$1.aggregateId,
            ),
          ],
        );
        await syncPersistence.updateEventSyncStatus(
          entry.$1.eventId,
          'delivered',
          serverSequence: entry.$2,
        );
        await categoriaProjectionStore.advanceLastServerSequence(
          entry.$1.aggregateId,
          entry.$2,
        );
      }

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
        await syncPersistence.updateEventSyncStatus(
          event.eventId,
          'conflict',
          rejectionReason: 'Conflicto de prueba.',
        );
      }

      final restorer = CategoriaMovidaConflictProjectionRestorer(
        categoriaProjectionStore,
      );
      await restorer.restore(movementB);
      await restorer.restore(movementA);

      final service = SyncConflictReportService(
        syncPersistence: syncPersistence,
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'http://localhost:3000',
        ),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final events = (body['events'] as List).cast<Map>();
          expect(events.map((event) => event['event_id']), [
            movementA.eventId,
            movementB.eventId,
          ]);

          return http.Response(
            jsonEncode({
              'results': [
                for (var index = 0; index < events.length; index++)
                  {
                    'event_id': events[index]['event_id'],
                    'status': 'conflict',
                    'server_sequence': 12 + index,
                    'created_at_server': '2026-06-09T20:31:00.000Z',
                    'reason': 'Conflicto de prueba.',
                  },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final report = await service.reportLocalConflicts();
      final categories = await categoriaDao.obtenerCategorias();

      expect(report.total, 2);
      expect(report.conflicts, 2);
      expect(categories.map((category) => category.id), [
        'category_1',
        'category_2',
      ]);
      expect(categories.map((category) => category.sortOrder), [0, 1]);
      expect(categories.map((category) => category.version), [1, 1]);
      expect(categories.map((category) => category.lastEventId), [
        created1.eventId,
        created2.eventId,
      ]);
      expect(categories.map((category) => category.lastServerSequence), [5, 6]);
    },
  );
}

SyncEvent _localEspacioEvent() {
  return SyncEvent(
    eventId: 'local_event_1',
    aggregateType: 'espacio',
    aggregateId: 'local_space_1',
    eventType: 'espacio_creado',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.parse('2026-06-09T20:30:00.000Z'),
    baseVersion: 1,
    payload: const {
      'nombre': 'Terraza',
      'identificacion': 'terraza',
      'visibilidad': 'sin_restriccion',
    },
  );
}

SyncEvent _localCategoriaCreada({
  required String eventId,
  required String categoryId,
  required String name,
  required int sortOrder,
}) {
  return SyncEvent(
    eventId: eventId,
    aggregateType: 'category',
    aggregateId: categoryId,
    eventType: 'categoria_creada',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.utc(2026, 6, 9, 20, 29, sortOrder),
    baseVersion: 1,
    payload: {'name': name, 'color_key': 'cyan', 'sort_order': sortOrder},
  );
}

SyncEvent _localCategoriaMovidaA() {
  return SyncEvent(
    eventId: 'movement_a',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_movida',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.utc(2026, 6, 9, 20, 30),
    baseServerSequence: 5,
    baseVersion: 1,
    payload: const {
      'base_event_id': 'category_1_created',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 0, 'to': 1},
      },
      'displaced_category': {
        'category_id': 'category_2',
        'base_event_id': 'category_2_created',
        'base_version': 1,
        'base_server_sequence': 6,
        'sort_order': {'from': 1, 'to': 0},
      },
    },
  );
}

SyncEvent _localCategoriaMovidaB() {
  return SyncEvent(
    eventId: 'movement_b',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_movida',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.utc(2026, 6, 9, 20, 30, 1),
    baseServerSequence: 5,
    baseVersion: 2,
    payload: const {
      'base_event_id': 'movement_a',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 1, 'to': 0},
      },
      'displaced_category': {
        'category_id': 'category_2',
        'base_event_id': 'movement_a',
        'base_version': 2,
        'base_server_sequence': 6,
        'sort_order': {'from': 0, 'to': 1},
      },
    },
  );
}
