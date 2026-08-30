import 'package:drift/drift.dart';

import 'inventory_items.dart';

/// Libro mayor inmutable de movimientos de inventario.
@DataClassName('InventoryMovementRow')
class InventoryMovements extends Table {
  /// UUID global del movimiento generado en el dispositivo.
  TextColumn get movementId => text()();

  /// Recurso cuyo saldo modifica el movimiento.
  TextColumn get inventoryItemId =>
      text().references(InventoryItems, #id, onDelete: KeyAction.restrict)();

  /// Renglón de venta causante, cuando el movimiento provenga de una venta.
  TextColumn get saleItemId => text().nullable()();

  /// Evento auditable que originó este movimiento.
  TextColumn get eventId => text()();

  /// Movimiento original cuando este registro sea una reversión.
  TextColumn get reversalOfMovementId => text().nullable().references(
    InventoryMovements,
    #movementId,
    onDelete: KeyAction.restrict,
  )();

  /// Clasificación estable del movimiento.
  TextColumn get movementType => text().withLength(min: 1, max: 40)();

  /// Delta atómico entero, positivo o negativo, pero nunca cero.
  IntColumn get quantityDeltaAtomic => integer().customConstraint(
    'NOT NULL CHECK (quantity_delta_atomic <> 0)',
  )();

  /// Costo total en unidad monetaria menor, cuando corresponda.
  IntColumn get totalCostMinor => integer().nullable()();

  /// Justificación normalizada; solo es obligatoria en correcciones manuales.
  TextColumn get reason => text().nullable()();

  /// Fecha capturada por el dispositivo al crear el movimiento.
  DateTimeColumn get createdAtLocal => dateTime()();

  /// Secuencia oficial asignada por el servidor.
  IntColumn get serverSequence => integer().nullable()();

  @override
  Set<Column> get primaryKey => {movementId};

  @override
  List<String> get customConstraints => const [
    "CHECK (reason IS NULL OR (reason = trim(reason) AND length(reason) BETWEEN 1 AND 500))",
    "CHECK (movement_type <> 'manual_adjustment' OR reason IS NOT NULL)",
    "CHECK (movement_type NOT IN ('initial_balance', 'stock_receipt') OR quantity_delta_atomic > 0)",
    "CHECK ((movement_type = 'reversal') = (reversal_of_movement_id IS NOT NULL))",
    'CHECK (reversal_of_movement_id IS NULL OR reversal_of_movement_id <> movement_id)',
  ];
}
