import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'cash_sessions.dart';
import 'sale_payments.dart';
import 'customer_payments.dart';
import 'financial_entries.dart';

/// Movimiento de cajón inmutable. createdEventId identifica la operación origen.
@DataClassName('CashMovementRow')
@TableIndex.sql(
  'CREATE INDEX ix_cash_movements_session ON cash_movements(session_id)',
)
class CashMovements extends Table with CommonFields {
  /// Apertura concreta; no se infiere por fechas.
  TextColumn get sessionId =>
      text().references(CashSessions, #id, onDelete: KeyAction.restrict)();

  /// Entrada in o salida out.
  TextColumn get direction => text()();

  /// Importe aplicado, sin cambio, en centavos.
  IntColumn get amountMinor => integer()();

  /// Pago de venta real; único y excluyente con los demás orígenes.
  TextColumn get salePaymentId => text().nullable().unique().references(
    SalePayments,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Abono real; único y excluyente con los demás orígenes.
  TextColumn get customerPaymentId => text().nullable().unique().references(
    CustomerPayments,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Registro adicional explícitamente asignado a este cajón.
  TextColumn get financialEntryId => text().nullable().unique().references(
    FinancialEntries,
    #id,
    onDelete: KeyAction.restrict,
  )();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK(direction IN ('in','out'))",
    'CHECK(amount_minor > 0 AND amount_minor <= 9007199254740991)',
    'CHECK((sale_payment_id IS NOT NULL) + (customer_payment_id IS NOT NULL) + (financial_entry_id IS NOT NULL) = 1)',
  ];
}
