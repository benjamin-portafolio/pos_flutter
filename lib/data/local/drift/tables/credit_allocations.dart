import 'package:drift/drift.dart';
import 'credit_sales.dart';
import 'customer_payments.dart';

/// Proyección FIFO reconstruible. No usa CommonFields porque su identidad es
/// el par abono/crédito y no tiene eventos ni ciclo de vida independientes.
class CreditAllocations extends Table {
  /// Abono cuyo importe se distribuye.
  TextColumn get paymentId => text().references(CustomerPayments, #id)();

  /// Crédito que recibe parte del abono.
  TextColumn get creditId => text().references(CreditSales, #id)();

  /// Parte positiva del abono aplicada a este crédito, en centavos.
  IntColumn get amountMinor => integer().customConstraint(
    'NOT NULL CHECK(amount_minor > 0 AND amount_minor <= 9007199254740991)',
  )();
  @override
  Set<Column> get primaryKey => {paymentId, creditId};
}
