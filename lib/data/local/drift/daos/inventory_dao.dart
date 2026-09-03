part of '../app_database.dart';

@DriftAccessor(
  tables: [
    Units,
    InventoryItems,
    InventoryBalances,
    InventoryMovements,
    RecipeComponents,
  ],
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
      case 'ingredients':
        predicates.add('''
          EXISTS (
            SELECT 1
            FROM recipe_components rc
            WHERE rc.inventory_item_id = ii.id
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
      readsFrom: {
        inventoryItems,
        inventoryBalances,
        units,
        db.productVariants,
        recipeComponents,
      },
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

  Future<InventoryBalanceRow?> obtenerSaldoPorRecursoId(String id) {
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

  Future<void> actualizarRecurso({
    required InventoryItemsCompanion item,
    required String inventoryItemId,
    required String expectedBaseEventId,
    required int expectedBaseVersion,
  }) async {
    final affected =
        await (update(inventoryItems)..where(
              (row) =>
                  row.id.equals(inventoryItemId) &
                  row.lastEventId.equals(expectedBaseEventId) &
                  row.version.equals(expectedBaseVersion),
            ))
            .write(item);
    if (affected != 1) {
      throw StateError('El recurso cambió durante la actualización.');
    }
  }

  Future<void> registrarMovimiento({
    required InventoryItemsCompanion item,
    required InventoryBalancesCompanion balance,
    required InventoryMovementsCompanion movement,
    required String inventoryItemId,
    required String expectedBaseEventId,
    required int expectedBaseVersion,
  }) {
    return db.transaction(() async {
      final itemAffected =
          await (update(inventoryItems)..where(
                (row) =>
                    row.id.equals(inventoryItemId) &
                    row.lastEventId.equals(expectedBaseEventId) &
                    row.version.equals(expectedBaseVersion),
              ))
              .write(item);
      if (itemAffected != 1) {
        throw StateError('El recurso cambió durante el movimiento.');
      }
      final balanceAffected =
          await (update(inventoryBalances)
                ..where((row) => row.inventoryItemId.equals(inventoryItemId)))
              .write(balance);
      if (balanceAffected != 1) {
        throw StateError('No se encontró el saldo del recurso.');
      }
      await into(inventoryMovements).insert(movement);
    });
  }

  Future<void> avanzarSecuenciaEvento({
    required String inventoryItemId,
    required String eventId,
    required int serverSequence,
    required bool includesBalance,
  }) async {
    await (update(inventoryItems)..where(
          (item) =>
              item.id.equals(inventoryItemId) &
              item.lastEventId.equals(eventId) &
              (item.lastServerSequence.isNull() |
                  item.lastServerSequence.isSmallerThanValue(serverSequence)),
        ))
        .write(
          InventoryItemsCompanion(lastServerSequence: Value(serverSequence)),
        );
    if (includesBalance) {
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
            InventoryBalancesCompanion(
              lastServerSequence: Value(serverSequence),
            ),
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

  Future<void> restaurarActualizacionRecurso({
    required String inventoryItemId,
    required String eventId,
    required String baseEventId,
    required int baseVersion,
    required int? baseServerSequence,
    required String previousName,
    required String nextName,
  }) {
    return db.transaction(() async {
      final affected =
          await (update(inventoryItems)..where(
                (item) =>
                    item.id.equals(inventoryItemId) &
                    item.lastEventId.equals(eventId) &
                    item.version.equals(baseVersion + 1) &
                    item.name.equals(nextName),
              ))
              .write(
                InventoryItemsCompanion(
                  name: Value(previousName),
                  version: Value(baseVersion),
                  lastEventId: Value(baseEventId),
                  lastServerSequence: Value(baseServerSequence),
                ),
              );
      if (affected != 1) return;

      // Un movimiento dependiente restaurado en orden inverso deja
      // temporalmente esta actualización como base del saldo. La edición de
      // nombre nunca afectó cantidades, por lo que también se retira esa base.
      await (update(inventoryBalances)..where(
            (balance) =>
                balance.inventoryItemId.equals(inventoryItemId) &
                balance.lastEventId.equals(eventId),
          ))
          .write(
            InventoryBalancesCompanion(
              lastEventId: Value(baseEventId),
              lastServerSequence: Value(baseServerSequence),
            ),
          );
    });
  }

  Future<void> restaurarMovimiento({
    required String inventoryItemId,
    required String eventId,
    required String baseEventId,
    required int baseVersion,
    required int? baseServerSequence,
    required String movementId,
    required int quantityDeltaAtomic,
  }) {
    return db.transaction(() async {
      final movement =
          await (select(inventoryMovements)..where(
                (row) =>
                    row.movementId.equals(movementId) &
                    row.inventoryItemId.equals(inventoryItemId) &
                    row.eventId.equals(eventId),
              ))
              .getSingleOrNull();
      if (movement == null) return;

      final itemAffected =
          await (update(inventoryItems)..where(
                (item) =>
                    item.id.equals(inventoryItemId) &
                    item.lastEventId.equals(eventId) &
                    item.version.equals(baseVersion + 1),
              ))
              .write(
                InventoryItemsCompanion(
                  version: Value(baseVersion),
                  lastEventId: Value(baseEventId),
                  lastServerSequence: Value(baseServerSequence),
                ),
              );
      if (itemAffected != 1) return;

      final balance =
          await (select(inventoryBalances)..where(
                (row) =>
                    row.inventoryItemId.equals(inventoryItemId) &
                    row.lastEventId.equals(eventId),
              ))
              .getSingleOrNull();
      if (balance == null) {
        throw StateError(
          'No se encontró el saldo local que se debe restaurar.',
        );
      }
      await (update(
        inventoryBalances,
      )..where((row) => row.inventoryItemId.equals(inventoryItemId))).write(
        InventoryBalancesCompanion(
          quantityOnHandAtomic: Value(
            balance.quantityOnHandAtomic - quantityDeltaAtomic,
          ),
          quantityAvailableAtomic: Value(
            balance.quantityAvailableAtomic - quantityDeltaAtomic,
          ),
          version: Value(balance.version - 1),
          lastEventId: Value(baseEventId),
          lastServerSequence: Value(baseServerSequence),
        ),
      );
      await (delete(inventoryMovements)..where(
            (row) =>
                row.movementId.equals(movementId) & row.eventId.equals(eventId),
          ))
          .go();
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
