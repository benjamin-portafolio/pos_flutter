import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  test(
    'consulta por identidad incluye saldo cero y omite inexistentes o inactivos',
    () async {
      await _insertResource(db, id: 'item-empty', name: 'Vacío', quantity: 0);
      final resource = await repository.watchRecursoPorId('item-empty').first;
      expect(resource?.id, 'item-empty');
      expect(resource?.existenciaAtomica, 0);
      expect(resource?.unidadPredeterminada.id, InventoryUnitIds.gram);
      expect(await repository.watchRecursoPorId('missing').first, isNull);
      expect(await repository.watchRecursoPorId('item-yeast').first, isNull);
    },
  );

  test('observa cambios del saldo vigente y la desactivación', () async {
    final emitted = <int?>[];
    final negativeBalance = repository
        .watchRecursoPorId('item-flour')
        .firstWhere((resource) => resource?.existenciaAtomica == -500);
    final subscription = repository
        .watchRecursoPorId('item-flour')
        .listen((resource) => emitted.add(resource?.existenciaAtomica));
    await repository.watchRecursoPorId('item-flour').first;
    await (db.update(
      db.inventoryBalances,
    )..where((balance) => balance.inventoryItemId.equals('item-flour'))).write(
      const InventoryBalancesCompanion(quantityOnHandAtomic: Value(-500)),
    );
    expect((await negativeBalance)?.existenciaAtomica, -500);
    final inactive = repository
        .watchRecursoPorId('item-flour')
        .firstWhere((resource) => resource == null);
    await (db.update(db.inventoryItems)
          ..where((item) => item.id.equals('item-flour')))
        .write(const InventoryItemsCompanion(active: Value(false)));
    expect(await inactive, isNull);
    expect(emitted, containsAllInOrder([2500, -500]));
    await subscription.cancel();
  });

  test(
    'historial filtra recurso, tipo y periodo antes del límite; desempata por id',
    () async {
      final day = DateTime(2026, 11, 20);
      Future<void> insert(
        String id,
        DateTime date, {
        String resource = 'item-flour',
        String type = 'stock_receipt',
      }) => db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              movementId: id,
              inventoryItemId: resource,
              eventId: 'event-$id',
              movementType: type,
              quantityDeltaAtomic: type == 'manual_adjustment' ? -200 : 1000,
              totalCostMinor: const Value(2500),
              reason: const Value('Conteo físico'),
              createdAtLocal: date,
            ),
          )
          .then((_) {});
      await insert('a', day);
      await insert('b', day);
      await insert(
        'c',
        day.add(const Duration(hours: 23)),
        type: 'manual_adjustment',
      );
      await insert('next-day', day.add(const Duration(days: 1)));
      await insert(
        'other-resource',
        day.add(const Duration(hours: 2)),
        resource: 'item-salt',
      );
      final result = await repository
          .watchMovimientos(
            'item-flour',
            desde: day,
            hasta: day.add(const Duration(days: 1)),
            limit: 2,
          )
          .first;
      expect(result.map((m) => m.id), ['c', 'b']);
      expect(result.first.quantityDeltaAtomic, -200);
      expect(result.first.totalCostMinor, 2500);
      expect(result.first.reason, 'Conteo físico');
      expect(result.first.eventId, 'event-c');
      expect(result.first.createdAtLocal, day.add(const Duration(hours: 23)));
      expect(
        (await repository
                .watchMovimientos(
                  'item-flour',
                  movementType: 'stock_receipt',
                  desde: day,
                  hasta: day.add(const Duration(days: 1)),
                  limit: 1,
                )
                .first)
            .single
            .id,
        'b',
      );
      expect(await repository.watchMovimientos('missing').first, isEmpty);
      expect(
        () => repository.watchMovimientos('item-flour', limit: 0),
        throwsArgumentError,
      );
      final updated = repository
          .watchMovimientos('item-flour')
          .firstWhere((rows) => rows.length == 5);
      await insert('live', day.add(const Duration(days: 2)));
      expect((await updated).first.id, 'live');
    },
  );

  test(
    'historial resuelve la venta desde la línea y conserva compensaciones',
    () async {
      await _linkResourceToProductVariant(db, 'item-flour');
      final date = DateTime(2026, 11, 20);
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: 'sale',
              userId: 'user',
              deviceId: 'device',
              totalMinor: 100,
              createdAtLocal: date,
              updatedAtLocal: date,
            ),
          );
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              id: 'line',
              saleId: 'sale',
              variantId: 'variant-flour',
              productNameSnapshot: 'Harina',
              saleModeSnapshot: 'unit',
              quantity: const Value(1),
              unitPriceMinor: 100,
              totalMinor: 100,
              sortOrder: 0,
            ),
          );
      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              movementId: 'consumption',
              inventoryItemId: 'item-flour',
              saleItemId: const Value('line'),
              eventId: 'sale-event',
              movementType: 'sale_consumption',
              quantityDeltaAtomic: -1000,
              createdAtLocal: date,
            ),
          );
      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              movementId: 'reversal',
              inventoryItemId: 'item-flour',
              eventId: 'reversal-event',
              movementType: 'reversal',
              quantityDeltaAtomic: 1000,
              reversalOfMovementId: const Value('consumption'),
              createdAtLocal: date.add(const Duration(hours: 1)),
            ),
          );
      final rows = await repository.watchMovimientos('item-flour').first;
      expect(rows.first.reversalOfMovementId, 'consumption');
      expect(rows.last.saleId, 'sale');
      expect(rows.last.saleItemId, 'line');
    },
  );

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
          sortOrder: 0,
          createdEventId: const Value('event-seed'),
          lastEventId: const Value('event-seed'),
        ),
      );
}
