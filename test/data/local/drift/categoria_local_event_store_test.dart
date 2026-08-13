import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/projections/categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late EventDao eventDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    eventDao = EventDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('server_sync guarda categoria, evento y event_ref pendiente', () async {
    final store = _store(AppMode.serverSync, db, categoriaDao, eventDao);

    await store.appendAndApply(
      _event(),
      refs: const [
        LocalEventRef.affects(refType: 'category', refId: 'category_1'),
      ],
    );

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    final event = (await eventDao.obtenerEventosPendientes()).single;
    final ref = (await db.select(db.eventRefs).get()).single;
    expect(categoria?.name, 'Bebidas');
    expect(event.deliveryStatus, 'pending');
    expect(ref.refType, 'category');
    expect(ref.source, 'local_pending');
  });

  test('standalone aplica categoria sin persistir event_refs', () async {
    final store = _store(AppMode.standalone, db, categoriaDao, eventDao);

    await store.appendAndApply(
      _event(),
      refs: const [
        LocalEventRef.affects(refType: 'category', refId: 'category_1'),
      ],
    );

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    final event = (await db.select(db.events).get()).single;
    final refs = await db.select(db.eventRefs).get();
    expect(categoria?.name, 'Bebidas');
    expect(event.deliveryStatus, 'not_required');
    expect(refs, isEmpty);
  });

  test('server_sync aplica edición y conserva el evento pendiente', () async {
    final store = _store(AppMode.serverSync, db, categoriaDao, eventDao);
    const refs = [
      LocalEventRef.affects(refType: 'category', refId: 'category_1'),
    ];

    await store.appendAndApply(_event(), refs: refs);
    await store.appendAndApply(_updatedEvent(), refs: refs);

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    final events = await eventDao.obtenerEventosPendientes();
    final storedRefs = await db.select(db.eventRefs).get();
    expect(categoria?.name, 'Bebidas frías');
    expect(categoria?.version, 2);
    expect(events.map((event) => event.eventType), [
      'categoria_creada',
      'categoria_actualizada',
    ]);
    expect(storedRefs, hasLength(2));
  });

  test('standalone aplica edición sin persistir event_refs', () async {
    final store = _store(AppMode.standalone, db, categoriaDao, eventDao);
    const refs = [
      LocalEventRef.affects(refType: 'category', refId: 'category_1'),
    ];

    await store.appendAndApply(_event(), refs: refs);
    await store.appendAndApply(_updatedEvent(), refs: refs);

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    final events = await db.select(db.events).get();
    expect(categoria?.name, 'Bebidas frías');
    expect(categoria?.version, 2);
    expect(events.map((event) => event.deliveryStatus).toSet(), {
      'not_required',
    });
    expect(await db.select(db.eventRefs).get(), isEmpty);
  });

  for (final mode in [AppMode.serverSync, AppMode.standalone]) {
    test('${mode.name} intercambia dos categorías de forma atómica', () async {
      final store = _store(mode, db, categoriaDao, eventDao);
      await store.appendAndApply(
        _event(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );
      await store.appendAndApply(
        _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
        ],
      );

      await store.appendAndApply(
        _movedEvent(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );

      final categories = await categoriaDao.obtenerCategorias();
      expect(categories.map((category) => category.id), [
        'category_2',
        'category_1',
      ]);
      expect(categories.map((category) => category.sortOrder), [0, 1]);
      final refs = await db.select(db.eventRefs).get();
      expect(refs, mode == AppMode.serverSync ? hasLength(4) : isEmpty);
      final move = await (db.select(
        db.events,
      )..where((event) => event.eventId.equals('event_3'))).getSingle();
      expect(
        move.deliveryStatus,
        mode == AppMode.serverSync ? 'pending' : 'not_required',
      );
    });

    test(
      '${mode.name} elimina y compacta categorías de forma atómica',
      () async {
        final store = _store(mode, db, categoriaDao, eventDao);
        await store.appendAndApply(
          _event(),
          refs: const [
            LocalEventRef.affects(refType: 'category', refId: 'category_1'),
          ],
        );
        await store.appendAndApply(
          _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
          refs: const [
            LocalEventRef.affects(refType: 'category', refId: 'category_2'),
          ],
        );

        await store.appendAndApply(
          _deletedEvent(),
          refs: const [
            LocalEventRef.affects(refType: 'category', refId: 'category_1'),
            LocalEventRef.affects(refType: 'category', refId: 'category_2'),
          ],
        );

        final categories = await categoriaDao.obtenerCategorias();
        expect(categories.single.id, 'category_2');
        expect(categories.single.sortOrder, 0);
        final refs = await db.select(db.eventRefs).get();
        expect(refs, mode == AppMode.serverSync ? hasLength(4) : isEmpty);
        final deletion = await (db.select(
          db.events,
        )..where((event) => event.eventId.equals('event_3'))).getSingle();
        expect(
          deletion.deliveryStatus,
          mode == AppMode.serverSync ? 'pending' : 'not_required',
        );
      },
    );

    test('${mode.name} mueve productos y guarda refs según el modo', () async {
      final store = _store(mode, db, categoriaDao, eventDao);
      await store.appendAndApply(
        _event(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );
      await store.appendAndApply(
        _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
        ],
      );
      await _insertProduct(db, 'product_1');

      await store.appendAndApply(
        _deletedWithProductEvent(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
          LocalEventRef.affects(refType: 'product', refId: 'product_1'),
          LocalEventRef.uses(refType: 'category', refId: 'category_2'),
        ],
      );

      final product = await (db.select(
        db.products,
      )..where((row) => row.id.equals('product_1'))).getSingle();
      expect(product.categoryId, 'category_2');
      expect(product.version, 3);
      expect(product.lastEventId, 'event_3');
      final deletion = await (db.select(
        db.events,
      )..where((event) => event.eventId.equals('event_3'))).getSingle();
      expect(
        deletion.deliveryStatus,
        mode == AppMode.serverSync ? 'pending' : 'not_required',
      );
      final refs = await db.select(db.eventRefs).get();
      expect(refs, mode == AppMode.serverSync ? hasLength(6) : isEmpty);
      if (mode == AppMode.serverSync) {
        expect(
          refs
              .where((ref) => ref.eventId == 'event_3')
              .map((ref) => '${ref.refType}:${ref.refId}:${ref.relationship}'),
          containsAll([
            'category:category_1:affects',
            'category:category_2:affects',
            'product:product_1:affects',
            'category:category_2:uses',
          ]),
        );
      }
    });
  }

  for (final scenario in const [
    (name: 'primera', count: 4, deletedIndex: 0),
    (name: 'intermedia', count: 4, deletedIndex: 2),
    (name: 'última', count: 4, deletedIndex: 3),
    (name: 'única', count: 1, deletedIndex: 0),
  ]) {
    test('elimina categoría ${scenario.name} y deja orden 0..n-1', () async {
      final store = _store(AppMode.serverSync, db, categoriaDao, eventDao);
      for (var index = 0; index < scenario.count; index++) {
        await store.appendAndApply(
          _event(
            eventId: 'event_$index',
            aggregateId: 'category_$index',
            sortOrder: index,
          ),
          refs: [
            LocalEventRef.affects(
              refType: 'category',
              refId: 'category_$index',
            ),
          ],
        );
      }

      final deletion = _deletedEventAt(
        count: scenario.count,
        deletedIndex: scenario.deletedIndex,
      );
      await store.appendAndApply(
        deletion,
        refs: [
          LocalEventRef.affects(
            refType: 'category',
            refId: deletion.aggregateId,
          ),
          for (
            var index = scenario.deletedIndex + 1;
            index < scenario.count;
            index++
          )
            LocalEventRef.affects(
              refType: 'category',
              refId: 'category_$index',
            ),
        ],
      );

      final categories = await categoriaDao.obtenerCategorias();
      expect(categories.map((category) => category.id), [
        for (var index = 0; index < scenario.count; index++)
          if (index != scenario.deletedIndex) 'category_$index',
      ]);
      expect(
        categories.map((category) => category.sortOrder),
        List.generate(scenario.count - 1, (index) => index),
      );
    });
  }

  test('revierte evento, refs y proyección si falla la compactación', () async {
    final store = _store(AppMode.serverSync, db, categoriaDao, eventDao);
    for (var index = 0; index < 2; index++) {
      await store.appendAndApply(
        _event(
          eventId: 'event_$index',
          aggregateId: 'category_$index',
          sortOrder: index,
        ),
        refs: [
          LocalEventRef.affects(refType: 'category', refId: 'category_$index'),
        ],
      );
    }

    await expectLater(
      store.appendAndApply(
        _deletedEventAt(count: 2, deletedIndex: 0, shiftedBaseVersion: 99),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_0'),
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      ),
      throwsStateError,
    );

    final categories = await categoriaDao.obtenerCategorias();
    expect(categories.map((category) => category.id), [
      'category_0',
      'category_1',
    ]);
    expect(categories.map((category) => category.sortOrder), [0, 1]);
    expect(await db.select(db.events).get(), hasLength(2));
    expect(await db.select(db.eventRefs).get(), hasLength(2));
  });

  test(
    'revierte productos, categoría, evento y refs ante fallo intermedio',
    () async {
      final setupStore = _store(AppMode.serverSync, db, categoriaDao, eventDao);
      await setupStore.appendAndApply(
        _event(),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_1'),
        ],
      );
      await setupStore.appendAndApply(
        _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
        refs: const [
          LocalEventRef.affects(refType: 'category', refId: 'category_2'),
        ],
      );
      await _insertProduct(db, 'product_1');

      final productStore = DriftProductoProjectionStore(
        productoDao: ProductoDao(db),
      );
      final failingCategoryStore = _FailingCategoriaProjectionStore(
        DriftCategoriaProjectionStore(categoriaDao: categoriaDao),
      );
      final failingStore = DriftLocalEventStore(
        db: db,
        eventDao: eventDao,
        eventRefDao: EventRefDao(db),
        eventProcessor: EventProcessor(
          handlers: categoriaEventHandlers(
            CategoriaEventHandler(failingCategoryStore, productStore),
          ),
        ),
        appConfigController: AppConfigController(
          AppConfig.initial.copyWith(
            mode: AppMode.serverSync,
            setupCompleted: true,
          ),
        ),
      );

      await expectLater(
        failingStore.appendAndApply(
          _deletedWithProductEvent(),
          refs: const [
            LocalEventRef.affects(refType: 'category', refId: 'category_1'),
            LocalEventRef.affects(refType: 'category', refId: 'category_2'),
            LocalEventRef.affects(refType: 'product', refId: 'product_1'),
            LocalEventRef.uses(refType: 'category', refId: 'category_2'),
          ],
        ),
        throwsStateError,
      );

      final categories = await categoriaDao.obtenerCategorias();
      expect(categories.map((category) => category.id), [
        'category_1',
        'category_2',
      ]);
      expect(categories.map((category) => category.sortOrder), [0, 1]);
      final product = await ProductoDao(db).obtenerProductoPorId('product_1');
      expect(product?.categoryId, 'category_1');
      expect(product?.version, 2);
      expect(product?.lastEventId, 'product_event_1');
      expect(await db.select(db.events).get(), hasLength(2));
      expect(await db.select(db.eventRefs).get(), hasLength(2));
    },
  );
}

DriftLocalEventStore _store(
  AppMode mode,
  AppDatabase db,
  CategoriaDao categoriaDao,
  EventDao eventDao,
) {
  return DriftLocalEventStore(
    db: db,
    eventDao: eventDao,
    eventRefDao: EventRefDao(db),
    eventProcessor: EventProcessor(
      handlers: categoriaEventHandlers(
        CategoriaEventHandler(
          DriftCategoriaProjectionStore(categoriaDao: categoriaDao),
          DriftProductoProjectionStore(productoDao: ProductoDao(db)),
        ),
      ),
    ),
    appConfigController: AppConfigController(
      AppConfig.initial.copyWith(mode: mode, setupCompleted: true),
    ),
  );
}

SyncEvent _event({
  String eventId = 'event_1',
  String aggregateId = 'category_1',
  int sortOrder = 0,
}) {
  return SyncEvent(
    eventId: eventId,
    aggregateType: 'category',
    aggregateId: aggregateId,
    eventType: 'categoria_creada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026),
    payload: {'name': 'Bebidas', 'color_key': 'cyan', 'sort_order': sortOrder},
  );
}

SyncEvent _movedEvent() {
  return SyncEvent(
    eventId: 'event_3',
    aggregateType: 'category',
    aggregateId: 'category_2',
    eventType: 'categoria_movida',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026, 1, 3),
    payload: const {
      'base_event_id': 'event_2',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 1, 'to': 0},
      },
      'displaced_category': {
        'category_id': 'category_1',
        'base_event_id': 'event_1',
        'base_version': 1,
        'base_server_sequence': null,
        'sort_order': {'from': 0, 'to': 1},
      },
    },
  );
}

SyncEvent _deletedEvent() {
  return SyncEvent(
    eventId: 'event_3',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_eliminada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026, 1, 3),
    payload: const {
      'base_event_id': 'event_1',
      'deleted_category': {
        'name': 'Bebidas',
        'color_key': 'cyan',
        'sort_order': 0,
        'active': true,
        'created_event_id': 'event_1',
      },
      'product_resolution': {'type': 'none'},
      'linked_products': [],
      'shifted_categories': [
        {
          'category_id': 'category_2',
          'base_event_id': 'event_2',
          'base_version': 1,
          'base_server_sequence': null,
          'sort_order': {'from': 1, 'to': 0},
        },
      ],
    },
  );
}

SyncEvent _deletedWithProductEvent() {
  return SyncEvent(
    eventId: 'event_3',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_eliminada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026, 1, 3),
    payload: const {
      'base_event_id': 'event_1',
      'deleted_category': {
        'name': 'Bebidas',
        'color_key': 'cyan',
        'sort_order': 0,
        'active': true,
        'created_event_id': 'event_1',
      },
      'product_resolution': {
        'type': 'move',
        'destination_category': {
          'category_id': 'category_2',
          'base_event_id': 'event_2',
          'base_version': 1,
          'base_server_sequence': null,
        },
      },
      'linked_products': [
        {
          'product_id': 'product_1',
          'base_event_id': 'product_event_1',
          'base_version': 2,
          'base_server_sequence': null,
          'category_id': {'from': 'category_1', 'to': 'category_2'},
        },
      ],
      'shifted_categories': [
        {
          'category_id': 'category_2',
          'base_event_id': 'event_2',
          'base_version': 1,
          'base_server_sequence': null,
          'sort_order': {'from': 1, 'to': 0},
        },
      ],
    },
  );
}

Future<void> _insertProduct(AppDatabase db, String id) async {
  await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id,
          name: 'Producto',
          categoryId: const Value('category_1'),
          version: const Value(2),
          createdEventId: const Value('product_created_1'),
          lastEventId: const Value('product_event_1'),
        ),
      );
}

class _FailingCategoriaProjectionStore implements CategoriaProjectionStore {
  _FailingCategoriaProjectionStore(this.delegate);

  final CategoriaProjectionStore delegate;

  @override
  Future<CategoriaProjection?> findById(String id) => delegate.findById(id);

  @override
  Future<List<CategoriaProjection>> findAllOrdered() =>
      delegate.findAllOrdered();

  @override
  Future<void> deleteById(String id) => delegate.deleteById(id);

  @override
  Future<void> update(CategoriaProjection projection) {
    throw StateError('Fallo de compactación simulado.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncEvent _deletedEventAt({
  required int count,
  required int deletedIndex,
  int? shiftedBaseVersion,
}) {
  return SyncEvent(
    eventId: 'delete_$deletedIndex',
    aggregateType: 'category',
    aggregateId: 'category_$deletedIndex',
    eventType: 'categoria_eliminada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026, 1, 3),
    payload: {
      'base_event_id': 'event_$deletedIndex',
      'deleted_category': {
        'name': 'Bebidas',
        'color_key': 'cyan',
        'sort_order': deletedIndex,
        'active': true,
        'created_event_id': 'event_$deletedIndex',
      },
      'product_resolution': const {'type': 'none'},
      'linked_products': const <Object?>[],
      'shifted_categories': [
        for (var index = deletedIndex + 1; index < count; index++)
          {
            'category_id': 'category_$index',
            'base_event_id': 'event_$index',
            'base_version': shiftedBaseVersion ?? 1,
            'base_server_sequence': null,
            'sort_order': {'from': index, 'to': index - 1},
          },
      ],
    },
  );
}

SyncEvent _updatedEvent() {
  return SyncEvent(
    eventId: 'event_2',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_actualizada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026, 1, 2),
    payload: const {
      'base_event_id': 'event_1',
      'changed_fields': ['name'],
      'changes': {
        'name': {'from': 'Bebidas', 'to': 'Bebidas frías'},
      },
    },
  );
}
