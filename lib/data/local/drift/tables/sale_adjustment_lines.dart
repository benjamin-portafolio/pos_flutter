import 'package:drift/drift.dart';
import 'sale_adjustments.dart';
import 'sale_items.dart';

/// Libro inmutable con clave compuesta; no usa CommonFields porque una línea
/// no tiene versión/active ni identidad independiente del documento y origen.
@DataClassName('SaleAdjustmentLineRow')
class SaleAdjustmentLines extends Table {
  /// Documento compensatorio propietario.
  TextColumn get operationId => text().references(SaleAdjustments, #id)();

  /// Línea histórica, que no se modifica.
  TextColumn get saleItemId => text().references(SaleItems, #id)();

  /// Cantidad comercial devuelta en átomos históricos.
  IntColumn get quantityAtomic => integer()();

  /// Incremento monetario acumulado, admite cero.
  IntColumn get amountMinor => integer()();

  /// Costo recuperado; null conserva desconocimiento histórico.
  IntColumn get recoveredCostMinor => integer().nullable()();

  /// Destino declarado: void/restock/not_restockable/untracked.
  TextColumn get destination => text()();

  /// Justificación de mercancía no reintegrable.
  TextColumn get reason => text().nullable()();
  @override
  Set<Column> get primaryKey => {operationId, saleItemId};
  @override
  List<String> get customConstraints => [
    'CHECK(quantity_atomic BETWEEN 1 AND 9007199254740991)',
    'CHECK(amount_minor BETWEEN 0 AND 9007199254740991)',
    'CHECK(recovered_cost_minor IS NULL OR recovered_cost_minor BETWEEN 0 AND 9007199254740991)',
    "CHECK(destination IN ('void','restock','not_restockable','untracked'))",
    "CHECK(destination <> 'not_restockable' OR (reason IS NOT NULL AND length(trim(reason)) > 0))",
  ];
}
