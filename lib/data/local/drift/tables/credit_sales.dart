import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'clientes.dart';
import 'sales.dart';

/// Deuda original inmutable de una venta. El id coincide con el de la venta.
@TableIndex.sql(
  'CREATE INDEX ix_credit_sales_customer ON credit_sales(cliente_id, occurred_at_ms, id)',
)
@DataClassName('CreditSaleRow')
class CreditSales extends Table with CommonFields {
  /// Venta confirmada que origina la deuda.
  TextColumn get saleId => text().unique().references(Sales, #id)();

  /// Titular de la cuenta en MXN.
  TextColumn get clienteId => text().references(Clientes, #id)();

  /// Importe original en centavos, nunca se reduce al abonar.
  IntColumn get amountMinor => integer().customConstraint(
    'NOT NULL CHECK(amount_minor > 0 AND amount_minor <= 9007199254740991)',
  )();

  /// Fecha UTC en milisegundos; junto al id fija el orden FIFO entre dispositivos.
  IntColumn get occurredAtMs => integer()();
  @override
  Set<Column> get primaryKey => {id};
}
