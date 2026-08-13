import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late CategoriaEventHandler handler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    handler = CategoriaEventHandler(
      DriftCategoriaProjectionStore(categoriaDao: categoriaDao),
      DriftProductoProjectionStore(productoDao: ProductoDao(db)),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('aplica categoria_creada con orden consecutivo', () async {
    await handler.applyCategoriaCreada(_event());

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    expect(categoria, isNotNull);
    expect(categoria!.name, 'Bebidas');
    expect(categoria.colorKey, ColorCategoria.cyan.key);
    expect(categoria.sortOrder, 0);
  });

  test('es idempotente y completa metadata cuando llega por pull', () async {
    final local = _event();
    await handler.applyCategoriaCreada(local);
    await handler.applyCategoriaCreada(
      local.copyWith(serverSequence: 7, deliveryStatus: 'delivered'),
    );

    final categorias = await categoriaDao.obtenerCategorias();
    expect(categorias, hasLength(1));
    expect(categorias.single.createdEventId, 'event_1');
    expect(categorias.single.lastServerSequence, 7);
  });

  test('permite nombres duplicados con ids diferentes', () async {
    await handler.applyCategoriaCreada(_event());
    await handler.applyCategoriaCreada(
      _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
    );

    final categorias = await categoriaDao.obtenerCategorias();
    expect(categorias, hasLength(2));
    expect(categorias.map((categoria) => categoria.name).toSet(), {'Bebidas'});
  });

  test('aplica categoria_actualizada e incrementa su versión', () async {
    await handler.applyCategoriaCreada(_event());

    await handler.applyCategoriaActualizada(
      _updatedEvent(
        payload: const {
          'base_event_id': 'event_1',
          'changed_fields': ['name', 'color_key'],
          'changes': {
            'name': {'from': 'Bebidas', 'to': 'Bebidas frías'},
            'color_key': {'from': 'cyan', 'to': 'blue'},
          },
        },
      ),
    );

    final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
    expect(categoria!.name, 'Bebidas frías');
    expect(categoria.colorKey, 'blue');
    expect(categoria.version, 2);
    expect(categoria.lastEventId, 'event_updated');
  });

  test(
    'categoria_actualizada es idempotente cuando regresa por pull',
    () async {
      await handler.applyCategoriaCreada(_event());
      final local = _updatedEvent();
      await handler.applyCategoriaActualizada(local);
      await handler.applyCategoriaActualizada(
        local.copyWith(serverSequence: 9, deliveryStatus: 'delivered'),
      );

      final categoria = await categoriaDao.obtenerCategoriaPorId('category_1');
      expect(categoria!.name, 'Bebidas frías');
      expect(categoria.version, 2);
      expect(categoria.lastServerSequence, 9);
    },
  );

  test('categoria_movida intercambia ambas posiciones', () async {
    await handler.applyCategoriaCreada(_event());
    await handler.applyCategoriaCreada(
      _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
    );

    await handler.applyCategoriaMovida(_movedEvent());

    final categories = await categoriaDao.obtenerCategorias();
    expect(categories.map((category) => category.id), [
      'category_2',
      'category_1',
    ]);
    expect(categories.map((category) => category.sortOrder), [0, 1]);
    expect(categories.every((category) => category.version == 2), isTrue);
    expect(
      categories.every((category) => category.lastEventId == 'event_moved'),
      isTrue,
    );
  });

  test('categoria_movida es idempotente cuando regresa por pull', () async {
    await handler.applyCategoriaCreada(_event());
    await handler.applyCategoriaCreada(
      _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
    );
    final local = _movedEvent();
    await handler.applyCategoriaMovida(local);
    await handler.applyCategoriaMovida(
      local.copyWith(serverSequence: 12, deliveryStatus: 'delivered'),
    );

    final categories = await categoriaDao.obtenerCategorias();
    expect(categories.map((category) => category.sortOrder), [0, 1]);
    expect(categories.every((category) => category.version == 2), isTrue);
    expect(
      categories.every((category) => category.lastServerSequence == 12),
      isTrue,
    );
  });

  test('categoria_eliminada es idempotente y no compacta dos veces', () async {
    await handler.applyCategoriaCreada(_event());
    await handler.applyCategoriaCreada(
      _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
    );
    final deletion = _deletedEvent();

    await handler.applyCategoriaEliminada(deletion);
    await handler.applyCategoriaEliminada(deletion);

    final categories = await categoriaDao.obtenerCategorias();
    expect(categories.single.id, 'category_2');
    expect(categories.single.sortOrder, 0);
    expect(categories.single.version, 2);
  });

  test(
    'categoria_eliminada mueve productos activos e inactivos una sola vez',
    () async {
      await handler.applyCategoriaCreada(_event());
      await handler.applyCategoriaCreada(
        _event(eventId: 'event_2', aggregateId: 'category_2', sortOrder: 1),
      );
      await _insertProduct(db, id: 'product_1', active: true);
      await _insertProduct(db, id: 'product_2', active: false);
      final deletion = _deletedWithProductsEvent(move: true);

      await handler.applyCategoriaEliminada(deletion);
      await handler.applyCategoriaEliminada(deletion);

      final products = await db.select(db.products).get();
      expect(products.map((product) => product.categoryId).toSet(), {
        'category_2',
      });
      expect(
        products.map((product) => product.active),
        containsAll([true, false]),
      );
      expect(products.every((product) => product.version == 3), isTrue);
      expect(
        products.every((product) => product.lastEventId == 'event_deleted'),
        isTrue,
      );
      expect(await categoriaDao.obtenerCategoriaPorId('category_1'), isNull);
    },
  );

  test('categoria_eliminada deja varios productos sin categoría', () async {
    await handler.applyCategoriaCreada(_event());
    await _insertProduct(db, id: 'product_1', active: true);
    await _insertProduct(db, id: 'product_2', active: false);

    await handler.applyCategoriaEliminada(
      _deletedWithProductsEvent(move: false),
    );

    final products = await db.select(db.products).get();
    expect(products.every((product) => product.categoryId == null), isTrue);
    expect(products.every((product) => product.version == 3), isTrue);
  });

  test(
    'categoria_eliminada rechaza un producto concurrente no confirmado',
    () async {
      await handler.applyCategoriaCreada(_event());
      await _insertProduct(db, id: 'product_1', active: true);
      await _insertProduct(db, id: 'product_2', active: true);
      await _insertProduct(db, id: 'product_new', active: true);

      await expectLater(
        handler.applyCategoriaEliminada(_deletedWithProductsEvent(move: false)),
        throwsStateError,
      );
      expect(await categoriaDao.obtenerCategoriaPorId('category_1'), isNotNull);
      final products = await db.select(db.products).get();
      expect(
        products.every((product) => product.categoryId == 'category_1'),
        isTrue,
      );
    },
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
    eventId: 'event_moved',
    aggregateType: 'category',
    aggregateId: 'category_2',
    eventType: 'categoria_movida',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026),
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

SyncEvent _updatedEvent({
  Map<String, Object?> payload = const {
    'base_event_id': 'event_1',
    'changed_fields': ['name'],
    'changes': {
      'name': {'from': 'Bebidas', 'to': 'Bebidas frías'},
    },
  },
}) {
  return SyncEvent(
    eventId: 'event_updated',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_actualizada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026),
    payload: payload,
  );
}

SyncEvent _deletedEvent() {
  return SyncEvent(
    eventId: 'event_deleted',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_eliminada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026),
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

SyncEvent _deletedWithProductsEvent({required bool move}) {
  return SyncEvent(
    eventId: 'event_deleted',
    aggregateType: 'category',
    aggregateId: 'category_1',
    eventType: 'categoria_eliminada',
    deviceId: 'test_device',
    userId: 'test_user',
    baseVersion: 1,
    createdAtLocal: DateTime(2026),
    payload: {
      'base_event_id': 'event_1',
      'deleted_category': {
        'name': 'Bebidas',
        'color_key': 'cyan',
        'sort_order': 0,
        'active': true,
        'created_event_id': 'event_1',
      },
      'product_resolution': move
          ? {
              'type': 'move',
              'destination_category': {
                'category_id': 'category_2',
                'base_event_id': 'event_2',
                'base_version': 1,
                'base_server_sequence': null,
              },
            }
          : {'type': 'uncategorize'},
      'linked_products': [
        _linkedProduct('product_1', move: move),
        _linkedProduct('product_2', move: move),
      ],
      'shifted_categories': move
          ? [
              {
                'category_id': 'category_2',
                'base_event_id': 'event_2',
                'base_version': 1,
                'base_server_sequence': null,
                'sort_order': {'from': 1, 'to': 0},
              },
            ]
          : [],
    },
  );
}

Map<String, Object?> _linkedProduct(String id, {required bool move}) => {
  'product_id': id,
  'base_event_id': '${id}_base',
  'base_version': 2,
  'base_server_sequence': null,
  'category_id': {'from': 'category_1', 'to': move ? 'category_2' : null},
};

Future<void> _insertProduct(
  AppDatabase db, {
  required String id,
  required bool active,
}) async {
  await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: id,
          name: 'Producto $id',
          categoryId: const Value('category_1'),
          active: Value(active),
          version: const Value(2),
          createdEventId: Value('${id}_created'),
          lastEventId: Value('${id}_base'),
        ),
      );
}
