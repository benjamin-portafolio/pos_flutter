import 'package:drift/drift.dart';

import 'inventory_items.dart';

/// Saldo materializado uno-a-uno de un recurso. No usa `CommonFields` porque
/// carece de identidad y ciclo de vida propios: su PK es la del recurso.
@DataClassName('InventoryBalanceRow')
class InventoryBalances extends Table {
  /// Recurso propietario y clave primaria del saldo.
  TextColumn get inventoryItemId =>
      text().references(InventoryItems, #id, onDelete: KeyAction.cascade)();

  /// Existencia física expresada exclusivamente en átomos enteros.
  IntColumn get quantityOnHandAtomic => integer()();

  /// Existencia disponible; en este alcance coincide con la existencia física.
  IntColumn get quantityAvailableAtomic => integer()();

  /// Último evento que cambió o creó el saldo.
  TextColumn get lastEventId => text()();

  /// Secuencia oficial más reciente aplicada al saldo.
  IntColumn get lastServerSequence => integer().nullable()();

  @override
  Set<Column> get primaryKey => {inventoryItemId};
}
