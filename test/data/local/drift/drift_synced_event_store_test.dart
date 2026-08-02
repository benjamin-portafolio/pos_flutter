import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late DriftCategoriaProjectionStore categoriaProjectionStore;
  late EventProcessor eventProcessor;
  late DriftLocalEventStore localEventStore;
  late ServerEchoAcknowledger serverEchoAcknowledger;
  late DriftSyncedEventStore syncedEventStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    categoriaProjectionStore = DriftCategoriaProjectionStore(
      categoriaDao: categoriaDao,
    );
    eventProcessor = EventProcessor(
      handlers: categoriaEventHandlers(
        CategoriaEventHandler(categoriaProjectionStore),
      ),
    );
    localEventStore = DriftLocalEventStore(
      db: db,
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      eventProcessor: eventProcessor,
      appConfigController: AppConfigController(
        AppConfig.initial.copyWith(
          mode: AppMode.serverSync,
          setupCompleted: true,
        ),
      ),
    );
    serverEchoAcknowledger = ServerEchoAcknowledger(
      categoriaProjectionStore: categoriaProjectionStore,
    );
    syncedEventStore = DriftSyncedEventStore(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'eco remoto de movimiento A conserva el movimiento local posterior B',
    () async {
      for (var index = 0; index < 3; index++) {
        final event = _createdEvent(index);
        await localEventStore.appendAndApply(
          event,
          refs: [
            LocalEventRef.affects(
              refType: 'category',
              refId: event.aggregateId,
            ),
          ],
        );
      }

      final movementA = _movementA();
      final movementB = _movementB();
      await localEventStore.appendAndApply(
        movementA,
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_3'),
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
        ],
      );
      await localEventStore.appendAndApply(
        movementB,
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_3'),
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );

      final serverTime = DateTime.utc(2026, 1, 3, 12);
      await syncedEventStore.applySyncedEvents(
        [
          movementA.copyWith(
            serverSequence: 12,
            createdAtServer: serverTime,
            deliveryStatus: 'delivered',
          ),
        ],
        applyEvent: eventProcessor.apply,
        acknowledgeEcho: serverEchoAcknowledger.acknowledge,
      );

      final categories = await categoriaDao.obtenerCategorias();
      expect(categories.map((category) => category.id), [
        'category_3',
        'category_1',
        'category_2',
      ]);
      expect(categories.map((category) => category.sortOrder), [0, 1, 2]);
      final movedCategory = categories.firstWhere(
        (category) => category.id == 'category_3',
      );
      expect(movedCategory.lastEventId, movementB.eventId);
      expect(movedCategory.lastServerSequence, 12);
      final displacedCategory = categories.firstWhere(
        (category) => category.id == 'category_2',
      );
      expect(displacedCategory.lastEventId, movementA.eventId);
      expect(displacedCategory.lastServerSequence, 12);
      final categoryOutsideMovement = categories.firstWhere(
        (category) => category.id == 'category_1',
      );
      expect(categoryOutsideMovement.lastServerSequence, null);

      final storedA = await (db.select(
        db.events,
      )..where((event) => event.eventId.equals(movementA.eventId))).getSingle();
      expect(storedA.deliveryStatus, 'delivered');
      expect(storedA.applicationStatus, 'applied');
      expect(storedA.serverSequence, 12);
      expect(storedA.createdAtServer?.toUtc(), serverTime);

      final refsA = await (db.select(
        db.eventRefs,
      )..where((ref) => ref.eventId.equals(movementA.eventId))).get();
      expect(refsA, hasLength(2));
      expect(refsA.map((ref) => ref.source).toSet(), {'server'});
      expect(refsA.map((ref) => ref.serverSequence).toSet(), {12});
    },
  );

  test(
    'evento remoto existente pero no aplicado conserva el flujo normal',
    () async {
      final event = _createdEvent(0);
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              eventId: event.eventId,
              aggregateType: event.aggregateType,
              aggregateId: event.aggregateId,
              eventType: event.eventType,
              deviceId: event.deviceId,
              userId: event.userId,
              baseVersion: Value(event.baseVersion),
              createdAtLocal: event.createdAtLocal,
              payload: event.payloadJson,
              applicationStatus: const Value('failed'),
              deliveryStatus: const Value('pending'),
            ),
          );

      await syncedEventStore.applySyncedEvents(
        [
          event.copyWith(
            serverSequence: 20,
            createdAtServer: DateTime.utc(2026, 1, 1, 12),
            deliveryStatus: 'delivered',
          ),
        ],
        applyEvent: eventProcessor.apply,
        acknowledgeEcho: serverEchoAcknowledger.acknowledge,
      );

      final category = await categoriaDao.obtenerCategoriaPorId('category_1');
      expect(category?.name, 'Categoría 1');
      final storedEvent = await (db.select(
        db.events,
      )..where((record) => record.eventId.equals(event.eventId))).getSingle();
      expect(storedEvent.applicationStatus, 'applied');
      expect(storedEvent.deliveryStatus, 'delivered');
      expect(storedEvent.serverSequence, 20);
    },
  );

  test('eco de categoría creada avanza solo su secuencia oficial', () async {
    final event = _createdEvent(0);
    await localEventStore.appendAndApply(
      event,
      refs: const [
        LocalEventRef.affects(refType: 'category', refId: 'category_1'),
      ],
    );

    await syncedEventStore.applySyncedEvents(
      [
        event.copyWith(
          serverSequence: 20,
          createdAtServer: DateTime.utc(2026, 1, 1, 12),
          deliveryStatus: 'delivered',
        ),
      ],
      applyEvent: eventProcessor.apply,
      acknowledgeEcho: serverEchoAcknowledger.acknowledge,
    );

    final category = await categoriaDao.obtenerCategoriaPorId('category_1');
    expect(category?.name, 'Categoría 1');
    expect(category?.sortOrder, 0);
    expect(category?.version, 1);
    expect(category?.lastEventId, event.eventId);
    expect(category?.lastServerSequence, 20);
  });
}

SyncEvent _createdEvent(int index) {
  final number = index + 1;
  return SyncEvent(
    eventId: 'event_created_$number',
    aggregateType: 'category',
    aggregateId: 'category_$number',
    eventType: 'categoria_creada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime.utc(2026, 1, 1, 0, 0, index),
    payload: {
      'name': 'Categoría $number',
      'color_key': 'neutral',
      'sort_order': index,
    },
  );
}

SyncEvent _movementA() {
  return SyncEvent(
    eventId: 'movement_a',
    aggregateType: 'category',
    aggregateId: 'category_3',
    eventType: 'categoria_movida',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime.utc(2026, 1, 2),
    payload: const {
      'base_event_id': 'event_created_3',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 2, 'to': 1},
      },
      'displaced_category': {
        'category_id': 'category_2',
        'base_event_id': 'event_created_2',
        'base_version': 1,
        'base_server_sequence': null,
        'sort_order': {'from': 1, 'to': 2},
      },
    },
  );
}

SyncEvent _movementB() {
  return SyncEvent(
    eventId: 'movement_b',
    aggregateType: 'category',
    aggregateId: 'category_3',
    eventType: 'categoria_movida',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 2,
    createdAtLocal: DateTime.utc(2026, 1, 3),
    payload: const {
      'base_event_id': 'movement_a',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 1, 'to': 0},
      },
      'displaced_category': {
        'category_id': 'category_1',
        'base_event_id': 'event_created_1',
        'base_version': 1,
        'base_server_sequence': null,
        'sort_order': {'from': 0, 'to': 1},
      },
    },
  );
}
