import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_eliminada_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/remote_event_preparer.dart';
import 'package:pos_flutter/application/sync/server_echo_acknowledger.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/projections/espacio_projection_store.dart';
import 'package:pos_flutter/application/sync/projections/producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late ProductoDao productoDao;
  late DriftLocalEventStore localStore;
  late RemoteEventApplier remoteApplier;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    productoDao = ProductoDao(db);
    final eventDao = EventDao(db);
    final eventRefDao = EventRefDao(db);
    final categoryStore = DriftCategoriaProjectionStore(
      categoriaDao: categoriaDao,
    );
    final productStore = DriftProductoProjectionStore(productoDao: productoDao);
    final categoryRestorer = CategoriaConflictProjectionRestorer(categoryStore);
    final movedRestorer = CategoriaMovidaConflictProjectionRestorer(
      categoryStore,
    );
    final deletedRestorer = CategoriaEliminadaConflictProjectionRestorer(
      categoryStore,
      productStore,
    );
    final cleaner = SyncConflictProjectionCleaner(
      espacioProjectionStore: _UnusedEspacioProjectionStore(),
      categoriaProjectionStore: categoryStore,
      productoProjectionStore: productStore,
      categoriaConflictProjectionRestorer: categoryRestorer,
      categoriaMovidaConflictProjectionRestorer: movedRestorer,
      categoriaEliminadaConflictProjectionRestorer: deletedRestorer,
    );
    final persistence = DriftSyncPersistence(
      db: db,
      eventDao: eventDao,
      eventRefDao: eventRefDao,
      syncCheckpointDao: SyncCheckpointDao(db),
    );
    final processor = EventProcessor(
      handlers: {
        ...categoriaEventHandlers(
          CategoriaEventHandler(categoryStore, productStore),
        ),
        ...productoEventHandlers(ProductoEventHandler(productStore)),
      },
    );
    localStore = DriftLocalEventStore(
      db: db,
      eventDao: eventDao,
      eventRefDao: eventRefDao,
      eventProcessor: processor,
    );
    remoteApplier = RemoteEventApplier(
      eventStore: DriftSyncedEventStore(db: db),
      eventProcessor: processor,
      serverEchoAcknowledger: ServerEchoAcknowledger(
        categoriaProjectionStore: categoryStore,
        productoProjectionStore: productStore,
      ),
      remoteEventPreparer: RemoteEventPreparer(
        syncPersistence: persistence,
        categoriaEliminadaConflictProjectionRestorer: deletedRestorer,
        conflictProjectionCleaner: cleaner,
      ),
    );
  });

  tearDown(() => db.close());

  test(
    'producto oficial restaura eliminación local y la pone en conflicto',
    () async {
      await remoteApplier.applySyncedEvents([_categoryCreated()]);
      await localStore.appendAndApply(
        _categoryDeleted(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );

      await remoteApplier.applySyncedEvents([_productCreated()]);

      expect(await categoriaDao.obtenerCategoriaPorId('category_1'), isNotNull);
      expect(await productoDao.obtenerProductoPorId('product_1'), isNotNull);
      final deletion = await (db.select(
        db.events,
      )..where((event) => event.eventId.equals('local_delete'))).getSingle();
      expect(deletion.deliveryStatus, 'conflict');
    },
  );

  test(
    'cambio oficial del destino restaura productos movidos y conserva lo oficial',
    () async {
      await remoteApplier.applySyncedEvents([
        _categoryCreated(),
        _destinationCategoryCreated(),
        _productCreated(serverSequence: 3),
      ]);
      await localStore.appendAndApply(
        _categoryDeletedMovingProduct(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
          LocalEventRef.affects(refType: 'product', refId: 'product_1'),
          LocalEventRef.uses(refType: 'category', refId: 'category_2'),
        ],
      );

      expect(await categoriaDao.obtenerCategoriaPorId('category_1'), isNull);
      expect(
        (await productoDao.obtenerProductoPorId('product_1'))?.categoryId,
        'category_2',
      );

      await remoteApplier.applySyncedEvents([_destinationCategoryUpdated()]);

      final source = await categoriaDao.obtenerCategoriaPorId('category_1');
      final destination = await categoriaDao.obtenerCategoriaPorId(
        'category_2',
      );
      final product = await productoDao.obtenerProductoPorId('product_1');
      expect(source, isNotNull);
      expect(destination?.name, 'Destino oficial');
      expect(destination?.version, 2);
      expect(product?.categoryId, 'category_1');
      expect(product?.version, 1);
      expect(product?.lastEventId, 'official_product');
      expect(product?.lastServerSequence, 3);
      final deletion = await (db.select(
        db.events,
      )..where((event) => event.eventId.equals('local_delete'))).getSingle();
      expect(deletion.deliveryStatus, 'conflict');
    },
  );

  test('restauración no sobrescribe un producto oficial posterior', () async {
    await remoteApplier.applySyncedEvents([
      _categoryCreated(),
      _destinationCategoryCreated(),
      _productCreated(serverSequence: 3),
    ]);
    await localStore.appendAndApply(
      _categoryDeletedMovingProduct(),
      refs: const [
        LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        LocalEventRef.affects(refType: 'category', refId: 'category_2'),
        LocalEventRef.affects(refType: 'product', refId: 'product_1'),
        LocalEventRef.uses(refType: 'category', refId: 'category_2'),
      ],
    );
    final productStore = DriftProductoProjectionStore(productoDao: productoDao);
    final current = await productStore.findProductById('product_1');
    await productStore.updateProduct(
      ProductoProjection(
        id: current!.id,
        nombre: current.nombre,
        categoriaId: null,
        active: current.active,
        version: 5,
        createdEventId: current.createdEventId,
        lastEventId: 'official_later',
        lastServerSequence: 9,
      ),
    );
    final categoryStore = DriftCategoriaProjectionStore(
      categoriaDao: categoriaDao,
    );

    await CategoriaEliminadaConflictProjectionRestorer(
      categoryStore,
      productStore,
    ).restore(_categoryDeletedMovingProduct());

    final preserved = await productoDao.obtenerProductoPorId('product_1');
    expect(preserved?.categoryId, isNull);
    expect(preserved?.version, 5);
    expect(preserved?.lastEventId, 'official_later');
    expect(preserved?.lastServerSequence, 9);
  });

  test(
    'eliminación oficial retira producto local pendiente antes del hard delete',
    () async {
      await remoteApplier.applySyncedEvents([_categoryCreated()]);
      await localStore.appendAndApply(
        _localProductCreated(),
        refs: const [
          LocalEventRef.affects(refType: 'product', refId: 'product_local'),
          LocalEventRef.affects(
            refType: 'product_variant',
            refId: 'variant_local',
          ),
          LocalEventRef(
            refType: 'category',
            refId: 'category_1',
            relationship: 'uses',
          ),
        ],
      );

      await remoteApplier.applySyncedEvents([
        _categoryDeleted(eventId: 'official_delete', serverSequence: 2),
      ]);

      expect(await categoriaDao.obtenerCategoriaPorId('category_1'), isNull);
      expect(await productoDao.obtenerProductoPorId('product_local'), isNull);
      final productEvent = await (db.select(
        db.events,
      )..where((event) => event.eventId.equals('local_product'))).getSingle();
      expect(productEvent.deliveryStatus, 'conflict');
    },
  );

  test(
    'cambio oficial restaura la categoría y prevalece sobre la eliminación local',
    () async {
      await remoteApplier.applySyncedEvents([_categoryCreated()]);
      await localStore.appendAndApply(
        _categoryDeleted(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );

      await remoteApplier.applySyncedEvents([_categoryUpdated()]);

      final category = await categoriaDao.obtenerCategoriaPorId('category_1');
      expect(category?.name, 'Bebidas oficiales');
      expect(category?.version, 2);
      final deletion = await (db.select(
        db.events,
      )..where((event) => event.eventId.equals('local_delete'))).getSingle();
      expect(deletion.deliveryStatus, 'conflict');
    },
  );

  test('una página remota fallida revierte preparación y aplicación', () async {
    await remoteApplier.applySyncedEvents([_categoryCreated()]);
    await localStore.appendAndApply(
      _categoryDeleted(),
      refs: const [
        LocalEventRef.affects(refType: 'category', refId: 'category_1'),
      ],
    );

    await expectLater(
      remoteApplier.applySyncedEvents(
        [_productCreated(), _unsupportedOfficialEvent()],
        afterApply: () =>
            SyncCheckpointDao(db).actualizarLastFullPullServerSequence(3),
      ),
      throwsUnsupportedError,
    );

    expect(await categoriaDao.obtenerCategoriaPorId('category_1'), isNull);
    expect(await productoDao.obtenerProductoPorId('product_1'), isNull);
    final deletion = await (db.select(
      db.events,
    )..where((event) => event.eventId.equals('local_delete'))).getSingle();
    expect(deletion.deliveryStatus, 'pending');
    expect(await SyncCheckpointDao(db).obtenerLastFullPullServerSequence(), 0);
  });
}

SyncEvent _categoryCreated() => SyncEvent(
  eventId: 'category_created',
  aggregateType: 'category',
  aggregateId: 'category_1',
  eventType: 'categoria_creada',
  deviceId: 'server_device',
  userId: 'user',
  serverSequence: 1,
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026),
  payload: const {'name': 'Bebidas', 'color_key': 'cyan', 'sort_order': 0},
);

SyncEvent _categoryDeleted({
  String eventId = 'local_delete',
  int? serverSequence,
}) => SyncEvent(
  eventId: eventId,
  aggregateType: 'category',
  aggregateId: 'category_1',
  eventType: 'categoria_eliminada',
  deviceId: serverSequence == null ? 'local_device' : 'server_device',
  userId: 'user',
  serverSequence: serverSequence,
  baseServerSequence: 1,
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026, 1, 2),
  payload: const {
    'base_event_id': 'category_created',
    'deleted_category': {
      'name': 'Bebidas',
      'color_key': 'cyan',
      'sort_order': 0,
      'active': true,
      'created_event_id': 'category_created',
    },
    'product_resolution': {'type': 'none'},
    'linked_products': [],
    'shifted_categories': [],
  },
);

SyncEvent _productCreated({int serverSequence = 2}) => SyncEvent(
  eventId: 'official_product',
  aggregateType: 'product',
  aggregateId: 'product_1',
  eventType: 'producto_creado',
  deviceId: 'server_device',
  userId: 'user',
  serverSequence: serverSequence,
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026, 1, 3),
  payload: _productPayload('variant_1'),
);

SyncEvent _destinationCategoryCreated() => SyncEvent(
  eventId: 'destination_created',
  aggregateType: 'category',
  aggregateId: 'category_2',
  eventType: 'categoria_creada',
  deviceId: 'server_device',
  userId: 'user',
  serverSequence: 2,
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026, 1, 2),
  payload: const {'name': 'Destino', 'color_key': 'amber', 'sort_order': 1},
);

SyncEvent _destinationCategoryUpdated() => SyncEvent(
  eventId: 'destination_updated',
  aggregateType: 'category',
  aggregateId: 'category_2',
  eventType: 'categoria_actualizada',
  deviceId: 'server_device',
  userId: 'user',
  serverSequence: 4,
  baseServerSequence: 2,
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026, 1, 4),
  payload: const {
    'base_event_id': 'destination_created',
    'changed_fields': ['name'],
    'changes': {
      'name': {'from': 'Destino', 'to': 'Destino oficial'},
    },
  },
);

SyncEvent _categoryDeletedMovingProduct() => SyncEvent(
  eventId: 'local_delete',
  aggregateType: 'category',
  aggregateId: 'category_1',
  eventType: 'categoria_eliminada',
  deviceId: 'local_device',
  userId: 'user',
  baseServerSequence: 1,
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026, 1, 3),
  payload: const {
    'base_event_id': 'category_created',
    'deleted_category': {
      'name': 'Bebidas',
      'color_key': 'cyan',
      'sort_order': 0,
      'active': true,
      'created_event_id': 'category_created',
    },
    'product_resolution': {
      'type': 'move',
      'destination_category': {
        'category_id': 'category_2',
        'base_event_id': 'destination_created',
        'base_version': 1,
        'base_server_sequence': 2,
      },
    },
    'linked_products': [
      {
        'product_id': 'product_1',
        'base_event_id': 'official_product',
        'base_version': 1,
        'base_server_sequence': 3,
        'category_id': {'from': 'category_1', 'to': 'category_2'},
      },
    ],
    'shifted_categories': [
      {
        'category_id': 'category_2',
        'base_event_id': 'destination_created',
        'base_version': 1,
        'base_server_sequence': 2,
        'sort_order': {'from': 1, 'to': 0},
      },
    ],
  },
);

SyncEvent _categoryUpdated() => SyncEvent(
  eventId: 'official_category_update',
  aggregateType: 'category',
  aggregateId: 'category_1',
  eventType: 'categoria_actualizada',
  deviceId: 'server_device',
  userId: 'user',
  serverSequence: 2,
  baseServerSequence: 1,
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026, 1, 3),
  payload: const {
    'base_event_id': 'category_created',
    'changed_fields': ['name'],
    'changes': {
      'name': {'from': 'Bebidas', 'to': 'Bebidas oficiales'},
    },
  },
);

SyncEvent _unsupportedOfficialEvent() => SyncEvent(
  eventId: 'unsupported_official',
  aggregateType: 'unknown',
  aggregateId: 'unknown_1',
  eventType: 'unknown_event',
  deviceId: 'server_device',
  userId: 'user',
  serverSequence: 3,
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026, 1, 4),
  payload: const {},
);

SyncEvent _localProductCreated() => SyncEvent(
  eventId: 'local_product',
  aggregateType: 'product',
  aggregateId: 'product_local',
  eventType: 'producto_creado',
  deviceId: 'local_device',
  userId: 'user',
  baseVersion: 1,
  createdAtLocal: DateTime.utc(2026, 1, 3),
  payload: _productPayload('variant_local'),
);

Map<String, Object?> _productPayload(String variantId) => {
  'product': {'name': 'Café', 'category_id': 'category_1'},
  'variants': [
    {
      'variant_id': variantId,
      'name': null,
      'sku': null,
      'barcode': null,
      'sale_price_minor': 1000,
      'is_default': true,
      'sort_order': 0,
      'inventory_configuration': {'behavior': 'none'},
    },
  ],
  'dependencies': [],
};

class _UnusedEspacioProjectionStore implements EspacioProjectionStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
