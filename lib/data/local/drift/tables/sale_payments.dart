import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'sales.dart';

/// Pago íntegro e inmutable. CommonFields identifica y audita la confirmación.
@DataClassName('SalePaymentRow')
class SalePayments extends Table with CommonFields {
  /// Una sola confirmación de pago directo por venta, incluso con otro event_id.
  TextColumn get saleId =>
      text().unique().references(Sales, #id, onDelete: KeyAction.restrict)();

  /// Importe aplicado al pago, excluyendo el cambio.
  IntColumn get amountMinor => integer()();

  /// Método real del pago directo; los pagos históricos son efectivo.
  TextColumn get method => text().withDefault(const Constant('cash'))();

  /// Referencia descriptiva opcional, normalizada al confirmar.
  TextColumn get reference => text().nullable()();

  /// Importe recibido por el método indicado.
  IntColumn get receivedMinor => integer()();

  /// Efectivo que se devuelve al cliente.
  IntColumn get changeMinor => integer()();

  /// Moneda del pago. Este flujo opera en MXN.
  TextColumn get currency => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    'CHECK(amount_minor >= 0 AND received_minor >= amount_minor AND received_minor <= 9007199254740991)',
    'CHECK(change_minor = received_minor - amount_minor)',
    "CHECK(currency = 'MXN')",
    "CHECK(method IN ('cash', 'transfer'))",
    "CHECK(method <> 'transfer' OR (received_minor = amount_minor AND change_minor = 0))",
    "CHECK(reference IS NULL OR length(reference) <= 500)",
  ];
}
