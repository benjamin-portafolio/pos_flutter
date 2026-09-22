import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'clientes.dart';

/// Abonos y anticipos inmutables de una cuenta de cliente en MXN.
@TableIndex.sql(
  'CREATE INDEX ix_customer_payments_customer ON customer_payments(cliente_id, occurred_at_ms, id)',
)
@DataClassName('CustomerPaymentRow')
class CustomerPayments extends Table with CommonFields {
  /// Cliente al que pertenece todo el abono, incluido el sobrante a favor.
  TextColumn get clienteId => text().references(Clientes, #id)();

  /// Dinero recibido en centavos; no incluye cambio entregado.
  IntColumn get amountMinor => integer().customConstraint(
    'NOT NULL CHECK(amount_minor > 0 AND amount_minor <= 9007199254740991)',
  )();

  /// Medio real por el que se recibió el dinero.
  TextColumn get method => text().customConstraint(
    "NOT NULL CHECK(method IN ('cash', 'transfer'))",
  )();

  /// Nota o referencia de transferencia opcional.
  TextColumn get reference => text().nullable()();

  /// Fecha UTC en milisegundos, conservada al sincronizar.
  IntColumn get occurredAtMs => integer()();
  @override
  Set<Column> get primaryKey => {id};
}
