import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late EspacioDao espacioDao;
  late EventDao eventDao;
  late EventRefDao eventRefDao;
  late ProductoDao productoDao;
  late SyncCheckpointDao checkpointDao;
  late DriftSyncPersistence syncPersistence;
  late DriftCategoriaProjectionStore categoriaProjectionStore;
  late DriftEspacioProjectionStore espacioProjectionStore;
  late DriftProductoProjectionStore productoProjectionStore;
  late DriftLocalEventStore localEventStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    espacioDao = EspacioDao(db);
    eventDao = EventDao(db);
    eventRefDao = EventRefDao(db);
    productoDao = ProductoDao(db);
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
    productoProjectionStore = DriftProductoProjectionStore(
      productoDao: productoDao,
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
          ...productoEventHandlers(
            ProductoEventHandler(productoProjectionStore),
          ),
        },
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'duplicate con original_sync_status conflict no marca delivered',
    () async {
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

      final service = SyncPushService(
        syncPersistence: syncPersistence,
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'http://localhost:3000',
        ),
        conflictProjectionCleaner: SyncConflictProjectionCleaner(
          espacioProjectionStore: espacioProjectionStore,
          categoriaProjectionStore: DriftCategoriaProjectionStore(
            categoriaDao: CategoriaDao(db),
          ),
          categoriaConflictProjectionRestorer:
              CategoriaConflictProjectionRestorer(
                DriftCategoriaProjectionStore(categoriaDao: CategoriaDao(db)),
              ),
          categoriaMovidaConflictProjectionRestorer:
              CategoriaMovidaConflictProjectionRestorer(
                DriftCategoriaProjectionStore(categoriaDao: CategoriaDao(db)),
              ),
        ),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/sync/push');

          return http.Response(
            jsonEncode({
              'results': [
                {
                  'event_id': 'local_event_1',
                  'status': 'duplicate',
                  'original_sync_status': 'conflict',
                  'server_sequence': 13,
                  'created_at_server': '2026-06-09T20:31:00.000Z',
                  'reason': 'Ya existe un espacio con identificacion terraza.',
                },
              ],
              'server_time': '2026-06-09T20:31:00.000Z',
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final report = await service.pushPendingEvents();
      final event = (await db.select(db.events).get()).single;
      final refs = await db.select(db.eventRefs).get();
      final espacios = await espacioDao.obtenerEspacios();

      expect(report.synced, 0);
      expect(report.conflicts, 1);
      expect(event.deliveryStatus, 'conflict');
      expect(event.serverSequence, 13);
      expect(event.rejectionReason, contains('identificacion terraza'));
      expect(refs.map((ref) => ref.source).toSet(), {'server'});
      expect(refs.map((ref) => ref.serverSequence).toSet(), {13});
      expect(espacios, isEmpty);
    },
  );

  test(
    'envía un evento dependiente después de entregar su base local',
    () async {
      final created = _localCategoriaCreada();
      final updated = _localCategoriaActualizada();
      await localEventStore.appendAndApply(
        created,
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );
      await localEventStore.appendAndApply(
        updated,
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );

      var requestCount = 0;
      final service = SyncPushService(
        syncPersistence: syncPersistence,
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'http://localhost:3000',
        ),
        conflictProjectionCleaner: SyncConflictProjectionCleaner(
          espacioProjectionStore: espacioProjectionStore,
          categoriaProjectionStore: categoriaProjectionStore,
          categoriaConflictProjectionRestorer:
              CategoriaConflictProjectionRestorer(categoriaProjectionStore),
          categoriaMovidaConflictProjectionRestorer:
              CategoriaMovidaConflictProjectionRestorer(
                categoriaProjectionStore,
              ),
        ),
        client: MockClient((request) async {
          requestCount++;
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final sentEvents = (body['events'] as List).cast<Map>();
          final expectedEvent = requestCount == 1 ? created : updated;
          expect(sentEvents, hasLength(1));
          expect(sentEvents.single['event_id'], expectedEvent.eventId);

          return http.Response(
            jsonEncode({
              'results': [
                {
                  'event_id': expectedEvent.eventId,
                  'status': 'accepted',
                  'server_sequence': requestCount,
                  'created_at_server': '2026-06-09T20:31:00.000Z',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final firstReport = await service.pushPendingEvents();
      var events = await db.select(db.events).get();
      expect(firstReport.total, 2);
      expect(firstReport.synced, 1);
      expect(firstReport.pending, 1);
      expect(
        events
            .singleWhere((event) => event.eventId == created.eventId)
            .deliveryStatus,
        'delivered',
      );
      expect(
        events
            .singleWhere((event) => event.eventId == updated.eventId)
            .deliveryStatus,
        'pending',
      );

      final secondReport = await service.pushPendingEvents();
      events = await db.select(db.events).get();
      expect(secondReport.total, 1);
      expect(secondReport.synced, 1);
      expect(secondReport.pending, 0);
      expect(requestCount, 2);
      expect(
        events
            .singleWhere((event) => event.eventId == updated.eventId)
            .deliveryStatus,
        'delivered',
      );
    },
  );

  test(
    'espera a entregar una categoría local antes de enviar el artículo',
    () async {
      final category = _localCategoriaCreada();
      final product = _localProductoCreado();
      await localEventStore.appendAndApply(
        category,
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );
      await localEventStore.appendAndApply(
        product,
        refs: const [
          LocalEventRef.affects(refType: 'product', refId: 'product_1'),
          LocalEventRef.affects(refType: 'product_variant', refId: 'variant_1'),
          LocalEventRef(
            refType: 'category',
            refId: 'category_1',
            relationship: 'uses',
          ),
        ],
      );

      var requestCount = 0;
      final service = SyncPushService(
        syncPersistence: syncPersistence,
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'http://localhost:3000',
        ),
        conflictProjectionCleaner: SyncConflictProjectionCleaner(
          espacioProjectionStore: espacioProjectionStore,
          categoriaProjectionStore: categoriaProjectionStore,
          productoProjectionStore: productoProjectionStore,
          categoriaConflictProjectionRestorer:
              CategoriaConflictProjectionRestorer(categoriaProjectionStore),
          categoriaMovidaConflictProjectionRestorer:
              CategoriaMovidaConflictProjectionRestorer(
                categoriaProjectionStore,
              ),
        ),
        client: MockClient((request) async {
          requestCount++;
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final sentEvents = (body['events'] as List).cast<Map>();
          final expected = requestCount == 1 ? category : product;
          expect(sentEvents, hasLength(1));
          expect(sentEvents.single['event_id'], expected.eventId);
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'event_id': expected.eventId,
                  'status': 'accepted',
                  'server_sequence': requestCount,
                  'created_at_server': '2026-08-05T20:31:00.000Z',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final first = await service.pushPendingEvents();
      final second = await service.pushPendingEvents();

      expect(first.synced, 1);
      expect(first.pending, 1);
      expect(second.synced, 1);
      expect(second.pending, 0);
      expect(requestCount, 2);
    },
  );

  test(
    'propaga el conflicto de la base y restaura movimientos dependientes',
    () async {
      final created1 = _localCategoriaCreada();
      final created2 = _localCategoria2Creada();
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
      }

      final service = SyncPushService(
        syncPersistence: syncPersistence,
        endpointConfig: SyncEndpointConfig(
          initialBaseUrl: 'http://localhost:3000',
        ),
        conflictProjectionCleaner: SyncConflictProjectionCleaner(
          espacioProjectionStore: espacioProjectionStore,
          categoriaProjectionStore: categoriaProjectionStore,
          categoriaConflictProjectionRestorer:
              CategoriaConflictProjectionRestorer(categoriaProjectionStore),
          categoriaMovidaConflictProjectionRestorer:
              CategoriaMovidaConflictProjectionRestorer(
                categoriaProjectionStore,
              ),
        ),
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          final sentEvents = (body['events'] as List).cast<Map>();
          expect(sentEvents, hasLength(1));
          expect(sentEvents.single['event_id'], movementA.eventId);

          return http.Response(
            jsonEncode({
              'results': [
                {
                  'event_id': movementA.eventId,
                  'status': 'conflict',
                  'server_sequence': 7,
                  'reason': 'El orden oficial ya cambió.',
                },
              ],
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );

      final report = await service.pushPendingEvents();
      final events = await db.select(db.events).get();
      final categories = await categoriaDao.obtenerCategorias();

      expect(report.total, 2);
      expect(report.conflicts, 2);
      expect(report.pending, 0);
      expect(
        events
            .where(
              (event) =>
                  event.eventId == movementA.eventId ||
                  event.eventId == movementB.eventId,
            )
            .map((event) => event.deliveryStatus)
            .toSet(),
        {'conflict'},
      );
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

SyncEvent _localCategoriaCreada() {
  return SyncEvent(
    eventId: 'local_category_created',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_creada',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.parse('2026-06-09T20:30:00.000Z'),
    baseVersion: 1,
    payload: const {'name': 'Bebidas', 'color_key': 'cyan', 'sort_order': 0},
  );
}

SyncEvent _localCategoriaActualizada() {
  return SyncEvent(
    eventId: 'local_category_updated',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_actualizada',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.parse('2026-06-09T20:30:01.000Z'),
    baseVersion: 1,
    payload: const {
      'base_event_id': 'local_category_created',
      'changed_fields': ['name'],
      'changes': {
        'name': {'from': 'Bebidas', 'to': 'Bebidas frías'},
      },
    },
  );
}

SyncEvent _localProductoCreado() {
  return SyncEvent(
    eventId: 'local_product_created',
    aggregateType: ProductoCreadoPayload.aggregateType,
    aggregateId: 'product_1',
    eventType: ProductoCreadoPayload.eventType,
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.parse('2026-08-05T20:30:01.000Z'),
    baseVersion: 1,
    payload: ProductoCreadoPayload.simple(
      nombre: 'Café',
      categoriaId: 'category_1',
      varianteId: 'variant_1',
      precioVentaMenor: 4550,
      dependenciaCategoria: const ProductoCreadoDependencia(
        refId: 'category_1',
        dependsOnEventId: 'local_category_created',
      ),
    ).toJson(),
  );
}

SyncEvent _localCategoria2Creada() {
  return SyncEvent(
    eventId: 'local_category_2_created',
    aggregateType: 'category',
    aggregateId: 'category_2',
    eventType: 'categoria_creada',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.parse('2026-06-09T20:30:00.500Z'),
    baseVersion: 1,
    payload: const {
      'name': 'Alimentos',
      'color_key': 'orange',
      'sort_order': 1,
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
    createdAtLocal: DateTime.utc(2026, 6, 9, 20, 32),
    baseServerSequence: 5,
    baseVersion: 1,
    payload: const {
      'base_event_id': 'local_category_created',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 0, 'to': 1},
      },
      'displaced_category': {
        'category_id': 'category_2',
        'base_event_id': 'local_category_2_created',
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
    createdAtLocal: DateTime.utc(2026, 6, 9, 20, 32, 1),
    baseServerSequence: 5,
    baseVersion: 2,
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
