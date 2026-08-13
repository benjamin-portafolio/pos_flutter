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
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late DriftCategoriaProjectionStore categoriaProjectionStore;
  late DriftProductoProjectionStore productoProjectionStore;
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
    productoProjectionStore = DriftProductoProjectionStore(
      productoDao: ProductoDao(db),
    );
    eventProcessor = EventProcessor(
      handlers: categoriaEventHandlers(
        CategoriaEventHandler(
          categoriaProjectionStore,
          productoProjectionStore,
        ),
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
      productoProjectionStore: productoProjectionStore,
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

  test('eco de categoria_eliminada no recrea ni compacta de nuevo', () async {
    final first = _createdEvent(0);
    final second = _createdEvent(1);
    for (final event in [first, second]) {
      await localEventStore.appendAndApply(
        event,
        refs: [
          LocalEventRef.affects(refType: 'category', refId: event.aggregateId),
        ],
      );
    }
    final deletion = _deletion();
    await localEventStore.appendAndApply(
      deletion,
      refs: const [
        LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        LocalEventRef.affects(refType: 'category', refId: 'category_2'),
      ],
    );

    await syncedEventStore.applySyncedEvents(
      [
        deletion.copyWith(
          serverSequence: 21,
          createdAtServer: DateTime.utc(2026, 1, 3, 12),
          deliveryStatus: 'delivered',
        ),
      ],
      applyEvent: eventProcessor.apply,
      acknowledgeEcho: serverEchoAcknowledger.acknowledge,
    );

    expect(
      await categoriaDao.obtenerCategoriaPorId('category_1'),
      equals(null),
    );
    final category = await categoriaDao.obtenerCategoriaPorId('category_2');
    expect(category?.sortOrder, 0);
    expect(category?.version, 2);
    expect(category?.lastEventId, deletion.eventId);
    expect(category?.lastServerSequence, 21);
  });

  test(
    'eco de categoria_eliminada completa metadata del producto una vez',
    () async {
      final first = _createdEvent(0);
      final second = _createdEvent(1);
      for (final event in [first, second]) {
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
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: 'product_1',
              name: 'Producto',
              categoryId: const Value('category_1'),
              version: const Value(2),
              createdEventId: const Value('product_created'),
              lastEventId: const Value('product_base'),
            ),
          );
      final deletion = _deletionWithProduct();
      await localEventStore.appendAndApply(
        deletion,
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
          LocalEventRef.affects(refType: 'product', refId: 'product_1'),
          LocalEventRef.uses(refType: 'category', refId: 'category_2'),
        ],
      );

      await syncedEventStore.applySyncedEvents(
        [deletion.copyWith(serverSequence: 21, deliveryStatus: 'delivered')],
        applyEvent: eventProcessor.apply,
        acknowledgeEcho: serverEchoAcknowledger.acknowledge,
      );

      final product = await ProductoDao(db).obtenerProductoPorId('product_1');
      expect(product?.categoryId, 'category_2');
      expect(product?.version, 3);
      expect(product?.lastEventId, deletion.eventId);
      expect(product?.lastServerSequence, 21);
    },
  );
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

SyncEvent _deletion() {
  return SyncEvent(
    eventId: 'deletion_1',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_eliminada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime.utc(2026, 1, 3),
    payload: const {
      'base_event_id': 'event_created_1',
      'deleted_category': {
        'name': 'Categoría 1',
        'color_key': 'neutral',
        'sort_order': 0,
        'active': true,
        'created_event_id': 'event_created_1',
      },
      'product_resolution': {'type': 'none'},
      'linked_products': [],
      'shifted_categories': [
        {
          'category_id': 'category_2',
          'base_event_id': 'event_created_2',
          'base_version': 1,
          'base_server_sequence': null,
          'sort_order': {'from': 1, 'to': 0},
        },
      ],
    },
  );
}

SyncEvent _deletionWithProduct() {
  return SyncEvent(
    eventId: 'deletion_product',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_eliminada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime.utc(2026, 1, 3),
    payload: const {
      'base_event_id': 'event_created_1',
      'deleted_category': {
        'name': 'Categoría 1',
        'color_key': 'neutral',
        'sort_order': 0,
        'active': true,
        'created_event_id': 'event_created_1',
      },
      'product_resolution': {
        'type': 'move',
        'destination_category': {
          'category_id': 'category_2',
          'base_event_id': 'event_created_2',
          'base_version': 1,
          'base_server_sequence': null,
        },
      },
      'linked_products': [
        {
          'product_id': 'product_1',
          'base_event_id': 'product_base',
          'base_version': 2,
          'base_server_sequence': null,
          'category_id': {'from': 'category_1', 'to': 'category_2'},
        },
      ],
      'shifted_categories': [
        {
          'category_id': 'category_2',
          'base_event_id': 'event_created_2',
          'base_version': 1,
          'base_server_sequence': null,
          'sort_order': {'from': 1, 'to': 0},
        },
      ],
    },
  );
}
