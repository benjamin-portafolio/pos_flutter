import 'package:drift/drift.dart';
import 'sale_adjustments.dart';
import 'credit_sales.dart';

/// Libro inmutable de reducción; no usa CommonFields: identidad es operación,
/// no admite edición/borrado lógico ni reemplaza el cargo original.
@DataClassName('SaleCreditReductionRow')
class SaleCreditReductions extends Table {
  /// Operación única responsable de la reducción.
  TextColumn get operationId => text().references(SaleAdjustments, #id)();

  /// Cargo histórico cuyo neto se reduce.
  TextColumn get creditId => text().references(CreditSales, #id)();

  /// Reducción positiva; residuos cero no crean filas.
  IntColumn get amountMinor => integer()();
  @override
  Set<Column> get primaryKey => {operationId};
  @override
  List<String> get customConstraints => [
    'CHECK(amount_minor BETWEEN 1 AND 9007199254740991)',
  ];
}
