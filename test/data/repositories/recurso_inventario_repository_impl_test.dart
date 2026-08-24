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

  test('aplica búsqueda y filtro de inactivos', () async {
    expect(
      (await repository
              .watchRecursos(filtro: InventoryResourceFilter.inactive)
              .first)
          .map((resource) => resource.nombre),
      ['Levadura'],
    );
    expect(
      (await repository.watchRecursos(busqueda: 'hari').first).single.nombre,
      'Harina',
    );
  });
}

Future<void> _seedResources(AppDatabase db) async {
  for (final item in [
    ('item-flour', 'Harina', true, InventoryUnitIds.kilogram, 2500),
    ('item-salt', 'Sal', true, InventoryUnitIds.gram, 100),
    ('item-yeast', 'Levadura', false, InventoryUnitIds.gram, 0),
  ]) {
    await db
        .into(db.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            id: item.$1,
            defaultUnitId: item.$4,
            name: item.$2,
            active: Value(item.$3),
            createdEventId: const Value('event-seed'),
            lastEventId: const Value('event-seed'),
          ),
        );
    await db
        .into(db.inventoryBalances)
        .insert(
          InventoryBalancesCompanion.insert(
            inventoryItemId: item.$1,
            quantityOnHandAtomic: item.$5,
            quantityAvailableAtomic: item.$5,
            lastEventId: 'event-seed',
          ),
        );
  }
}
