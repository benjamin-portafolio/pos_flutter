import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/projections/categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';

void main() {
  late AppDatabase db;
  late DriftCategoriaProjectionStore store;
  late CategoriaMovidaConflictProjectionRestorer restorer;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = DriftCategoriaProjectionStore(categoriaDao: CategoriaDao(db));
    restorer = CategoriaMovidaConflictProjectionRestorer(store);
    await store.insert(
      const CategoriaProjection(
        id: 'category_1',
        nombre: 'Bebidas',
        color: ColorCategoria.cyan,
        orden: 1,
        active: true,
        version: 2,
        createdEventId: 'created_1',
        lastEventId: 'move_1',
        lastServerSequence: 7,
      ),
    );
    await store.insert(
      const CategoriaProjection(
        id: 'category_2',
        nombre: 'Comidas',
        color: ColorCategoria.amber,
        orden: 0,
        active: true,
        version: 3,
        createdEventId: 'created_2',
        lastEventId: 'move_1',
        lastServerSequence: 8,
      ),
    );
  });

  tearDown(() => db.close());

  test('revierte las dos posiciones y sus bases', () async {
    await restorer.restore(_moveEvent());

    final moved = await store.findById('category_2');
    final displaced = await store.findById('category_1');
    expect(moved?.orden, 1);
    expect(moved?.version, 2);
    expect(moved?.lastEventId, 'base_2');
    expect(moved?.lastServerSequence, 8);
    expect(displaced?.orden, 0);
    expect(displaced?.version, 1);
    expect(displaced?.lastEventId, 'base_1');
    expect(displaced?.lastServerSequence, 7);
  });

  test('conserva la categoría que ya recibió un orden oficial', () async {
    await restorer.restore(
      _moveEvent(),
      officialCategoryIds: const {'category_2'},
    );

    final moved = await store.findById('category_2');
    final displaced = await store.findById('category_1');
    expect(moved?.orden, 0);
    expect(moved?.version, 3);
    expect(moved?.lastEventId, 'move_1');
    expect(displaced?.orden, 0);
    expect(displaced?.lastEventId, 'base_1');
  });
}

SyncEvent _moveEvent() {
  return SyncEvent(
    eventId: 'move_1',
    aggregateType: 'category',
    aggregateId: 'category_2',
    eventType: 'categoria_movida',
    deviceId: 'device',
    userId: 'user',
    baseVersion: 2,
    baseServerSequence: 8,
    createdAtLocal: DateTime(2026),
    payload: const {
      'base_event_id': 'base_2',
      'changed_fields': ['sort_order'],
      'changes': {
        'sort_order': {'from': 1, 'to': 0},
      },
      'displaced_category': {
        'category_id': 'category_1',
        'base_event_id': 'base_1',
        'base_version': 1,
        'base_server_sequence': 7,
        'sort_order': {'from': 0, 'to': 1},
      },
    },
  );
}
