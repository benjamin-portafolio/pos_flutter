part of '../app_database.dart';

@DriftAccessor(
  tables: [Units, InventoryItems, InventoryBalances, InventoryMovements],
)
class InventoryDao extends DatabaseAccessor<AppDatabase>
    with _$InventoryDaoMixin {
  InventoryDao(super.db);

  Stream<List<InventoryListingRow>> watchRecursos({
    String busqueda = '',
    String filtro = 'all',
  }) {
    final normalizedSearch = busqueda.trim().toLowerCase();
    final predicates = <String>[];
    final variables = <Variable<Object>>[];

    if (normalizedSearch.isNotEmpty) {
      predicates.add("LOWER(ii.name) LIKE ? ESCAPE '\\'");
      variables.add(Variable<String>('%${_escapeLike(normalizedSearch)}%'));
    }

    predicates.add('ii.active = 1');

    switch (filtro) {
      case 'products':
        predicates.add('''
          EXISTS (
            SELECT 1
            FROM product_variants pv
            WHERE pv.inventory_item_id = ii.id
          )
        ''');
      case 'independent':
        predicates.add('''
          NOT EXISTS (
            SELECT 1
            FROM product_variants pv
            WHERE pv.inventory_item_id = ii.id
          )
        ''');
      case 'with_stock':
        predicates.add('COALESCE(ib.quantity_on_hand_atomic, 0) > 0');
      case 'without_stock':
        predicates.add('COALESCE(ib.quantity_on_hand_atomic, 0) <= 0');
    }

    final where = predicates.isEmpty ? '' : 'WHERE ${predicates.join(' AND ')}';
    final query = customSelect(
      '''
        SELECT
          ii.id,
          ii.name,
          ii.active,
          COALESCE(ib.quantity_on_hand_atomic, 0) AS quantity_on_hand_atomic,
          u.unit_id,
          u.code AS unit_code,
          u.name AS unit_name,
          u.symbol,
          u.dimension,
          u.atomic_factor,
          u.max_fraction_digits,
          u.active AS unit_active
        FROM inventory_items ii
        JOIN units u ON u.unit_id = ii.default_unit_id
        LEFT JOIN inventory_balances ib ON ib.inventory_item_id = ii.id
        $where
        ORDER BY LOWER(ii.name), ii.id
      ''',
      variables: variables,
      readsFrom: {inventoryItems, inventoryBalances, units, db.productVariants},
    );
    return query.watch().map(
      (rows) =>
          rows.map(InventoryListingRow.fromQueryRow).toList(growable: false),
    );
  }

  Future<InventoryItemRow?> obtenerRecursoPorId(String id) {
    return (select(
      inventoryItems,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
  }

  Future<InventoryMovementRow?> obtenerMovimientoPorId(String id) {
    return (select(
      inventoryMovements,
    )..where((movement) => movement.movementId.equals(id))).getSingleOrNull();
  }

  Future<InventoryBalanceRow?> obtenerSaldoPorRecurso(String id) {
    return (select(inventoryBalances)
          ..where((balance) => balance.inventoryItemId.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertarCreacion({
    required InventoryItemsCompanion item,
    required InventoryBalancesCompanion balance,
    InventoryMovementsCompanion? movement,
  }) {
    return db.transaction(() async {
      await into(inventoryItems).insert(item);
      await into(inventoryBalances).insert(balance);
      if (movement != null) {
        await into(inventoryMovements).insert(movement);
      }
    });
  }

  Future<void> avanzarSecuenciaCreacion({
    required String inventoryItemId,
    required String eventId,
    required int serverSequence,
  }) async {
    await (update(inventoryItems)..where(
          (item) =>
              item.id.equals(inventoryItemId) &
              item.createdEventId.equals(eventId) &
              (item.lastServerSequence.isNull() |
                  item.lastServerSequence.isSmallerThanValue(serverSequence)),
        ))
        .write(
          InventoryItemsCompanion(lastServerSequence: Value(serverSequence)),
        );
    await (update(inventoryBalances)..where(
          (balance) =>
              balance.inventoryItemId.equals(inventoryItemId) &
              balance.lastEventId.equals(eventId) &
              (balance.lastServerSequence.isNull() |
                  balance.lastServerSequence.isSmallerThanValue(
                    serverSequence,
                  )),
        ))
        .write(
          InventoryBalancesCompanion(lastServerSequence: Value(serverSequence)),
        );
    await (update(inventoryMovements)..where(
          (movement) =>
              movement.inventoryItemId.equals(inventoryItemId) &
              movement.eventId.equals(eventId) &
              (movement.serverSequence.isNull() |
                  movement.serverSequence.isSmallerThanValue(serverSequence)),
        ))
        .write(
          InventoryMovementsCompanion(serverSequence: Value(serverSequence)),
        );
  }

  Future<void> aplicarAjuste({
    required String inventoryItemId,
    required int itemVersion,
    required InventoryBalancesCompanion balance,
    required InventoryMovementsCompanion movement,
  }) {
    return db.transaction(() async {
      await into(inventoryMovements).insert(movement);
      await (update(inventoryBalances)
            ..where((row) => row.inventoryItemId.equals(inventoryItemId)))
          .write(balance);
      await (update(
        inventoryItems,
      )..where((item) => item.id.equals(inventoryItemId))).write(
        InventoryItemsCompanion(
          version: Value(itemVersion),
          lastEventId: Value(movement.eventId.value),
          lastServerSequence: movement.serverSequence,
        ),
      );
    });
  }

  Future<void> avanzarSecuenciaAjuste({
    required String inventoryItemId,
    required String movementId,
    required String eventId,
    required int serverSequence,
  }) async {
    await (update(inventoryMovements)..where(
          (movement) =>
              movement.movementId.equals(movementId) &
              movement.eventId.equals(eventId),
        ))
        .write(
          InventoryMovementsCompanion(serverSequence: Value(serverSequence)),
        );
    await (update(inventoryBalances)..where(
          (balance) =>
              balance.inventoryItemId.equals(inventoryItemId) &
              balance.lastEventId.equals(eventId),
        ))
        .write(
          InventoryBalancesCompanion(lastServerSequence: Value(serverSequence)),
        );
    await (update(inventoryItems)..where(
          (item) =>
              item.id.equals(inventoryItemId) &
              (item.lastServerSequence.isNull() |
                  item.lastServerSequence.isSmallerThanValue(serverSequence)),
        ))
        .write(
          InventoryItemsCompanion(lastServerSequence: Value(serverSequence)),
        );
  }

  Future<void> eliminarAjustePorEvento(String eventId) {
    return db.transaction(() async {
      final movement = await (select(
        inventoryMovements,
      )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();
      if (movement == null) return;
      final balance = await obtenerSaldoPorRecurso(movement.inventoryItemId);
      final item = await obtenerRecursoPorId(movement.inventoryItemId);
      if (balance != null) {
        final restoredOnHand =
            balance.quantityOnHandAtomic - movement.quantityDeltaAtomic;
        final restoredAvailable =
            balance.quantityAvailableAtomic - movement.quantityDeltaAtomic;
        await (update(inventoryBalances)..where(
              (row) => row.inventoryItemId.equals(movement.inventoryItemId),
            ))
            .write(
              InventoryBalancesCompanion(
                quantityOnHandAtomic: Value(restoredOnHand),
                quantityAvailableAtomic: Value(restoredAvailable),
                lastEventId: Value(item?.createdEventId ?? eventId),
                lastServerSequence: Value(item?.lastServerSequence),
              ),
            );
      }
      await (delete(
        inventoryMovements,
      )..where((row) => row.eventId.equals(eventId))).go();
      if (item != null && item.lastEventId == eventId) {
        await (update(
          inventoryItems,
        )..where((row) => row.id.equals(item.id))).write(
          InventoryItemsCompanion(
            version: Value(item.version > 1 ? item.version - 1 : 1),
            lastEventId: Value(item.createdEventId),
          ),
        );
      }
    });
  }

  Future<void> eliminarCreacionPorEvento(String eventId) {
    return db.transaction(() async {
      await (delete(
        inventoryMovements,
      )..where((movement) => movement.eventId.equals(eventId))).go();
      await (delete(
        inventoryItems,
      )..where((item) => item.createdEventId.equals(eventId))).go();
    });
  }

  String _escapeLike(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}

class InventoryListingRow {
  const InventoryListingRow({
    required this.id,
    required this.name,
    required this.active,
    required this.quantityOnHandAtomic,
    required this.unitId,
    required this.unitCode,
    required this.unitName,
    required this.symbol,
    required this.dimension,
    required this.atomicFactor,
    required this.maxFractionDigits,
    required this.unitActive,
  });

  factory InventoryListingRow.fromQueryRow(QueryRow row) {
    return InventoryListingRow(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      active: row.read<bool>('active'),
      quantityOnHandAtomic: row.read<int>('quantity_on_hand_atomic'),
      unitId: row.read<String>('unit_id'),
      unitCode: row.read<String>('unit_code'),
      unitName: row.read<String>('unit_name'),
      symbol: row.read<String>('symbol'),
      dimension: row.read<String>('dimension'),
      atomicFactor: row.read<int>('atomic_factor'),
      maxFractionDigits: row.read<int>('max_fraction_digits'),
      unitActive: row.read<bool>('unit_active'),
    );
  }

  final String id;
  final String name;
  final bool active;
  final int quantityOnHandAtomic;
  final String unitId;
  final String unitCode;
  final String unitName;
  final String symbol;
  final String dimension;
  final int atomicFactor;
  final int maxFractionDigits;
  final bool unitActive;
}
