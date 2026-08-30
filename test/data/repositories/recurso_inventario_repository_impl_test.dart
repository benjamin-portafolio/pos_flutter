import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_resource_filter.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

void main() {
  late AppDatabase db;
  late RecursoInventarioRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = RecursoInventarioRepositoryImpl(
      inventoryDao: InventoryDao(db),
    );
    await db.customSelect('SELECT 1').get();
    await _seedResources(db);
  });

  tearDown(() => db.close());

  test('lista recursos activos con saldo y unidad', () async {
    final resources = await repository.watchRecursos().first;
    expect(resources.map((resource) => resource.nombre), ['Harina', 'Sal']);

    final flour = resources.first;
    expect(flour.existenciaAtomica, 2500);
    expect(flour.unidadPredeterminada.simbolo, 'kg');
  });

  test('aplica búsqueda solo sobre recursos activos', () async {
    expect(
      (await repository.watchRecursos(busqueda: 'hari').first).single.nombre,
      'Harina',
    );
    expect(await repository.watchRecursos(busqueda: 'leva').first, isEmpty);
  });

  test('filtra recursos de productos e independientes', () async {
    await _linkResourceToProductVariant(db, 'item-flour');

    expect(
      (await repository
              .watchRecursos(filtro: InventoryResourceFilter.products)
              .first)
          .map((resource) => resource.nombre),
      ['Harina'],
    );
    expect(
      (await repository
              .watchRecursos(filtro: InventoryResourceFilter.independent)
              .first)
          .map((resource) => resource.nombre),
      ['Sal'],
    );
  });

  test('filtra recursos con existencia y sin existencia', () async {
    await _insertResource(db, id: 'item-empty', name: 'Azúcar', quantity: 0);
    await _insertResource(
      db,
      id: 'item-negative',
      name: 'Aceite',
      quantity: -10,
    );

    expect(
      (await repository
              .watchRecursos(filtro: InventoryResourceFilter.withStock)
              .first)
          .map((resource) => resource.nombre),
      ['Harina', 'Sal'],
    );
    expect(
      (await repository
              .watchRecursos(filtro: InventoryResourceFilter.withoutStock)
              .first)
          .map((resource) => resource.nombre),
      ['Aceite', 'Azúcar'],
    );
  });
}

Future<void> _seedResources(AppDatabase db) async {
  for (final item in [
    ('item-flour', 'Harina', true, InventoryUnitIds.kilogram, 2500),
    ('item-salt', 'Sal', true, InventoryUnitIds.gram, 100),
    ('item-yeast', 'Levadura', false, InventoryUnitIds.gram, 0),
  ]) {
    await _insertResource(
      db,
      id: item.$1,
      name: item.$2,
      active: item.$3,
      unitId: item.$4,
      quantity: item.$5,
    );
  }
}

Future<void> _insertResource(
  AppDatabase db, {
  required String id,
  required String name,
  required int quantity,
  bool active = true,
  String unitId = InventoryUnitIds.gram,
}) async {
  await db
      .into(db.inventoryItems)
      .insert(
        InventoryItemsCompanion.insert(
          id: id,
          defaultUnitId: unitId,
          name: name,
          active: Value(active),
          createdEventId: const Value('event-seed'),
          lastEventId: const Value('event-seed'),
        ),
      );
  await db
      .into(db.inventoryBalances)
      .insert(
        InventoryBalancesCompanion.insert(
          inventoryItemId: id,
          quantityOnHandAtomic: quantity,
          quantityAvailableAtomic: quantity,
          lastEventId: 'event-seed',
        ),
      );
}

Future<void> _linkResourceToProductVariant(
  AppDatabase db,
  String inventoryItemId,
) async {
  await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          id: 'product-flour',
          name: 'Producto de harina',
          createdEventId: const Value('event-seed'),
          lastEventId: const Value('event-seed'),
        ),
      );
  await db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: 'variant-flour',
          productId: 'product-flour',
          salePriceMinor: 100,
          inventoryItemId: Value(inventoryItemId),
          isDefault: true,
          sortOrder: 0,
          createdEventId: const Value('event-seed'),
          lastEventId: const Value('event-seed'),
        ),
      );
}
