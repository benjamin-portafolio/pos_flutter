import 'package:drift/drift.dart';
import 'common_fields.dart';
import 'supplier_orders.dart';

/// Documento con trazabilidad propia; recepción inmutable una vez aplicada.
@DataClassName('SupplierReceiptRow')
@TableIndex.sql(
  'CREATE INDEX ix_supplier_receipts_lookup ON supplier_receipts (order_id, occurred_at_ms)',
)
class SupplierReceipts extends Table with CommonFields {
  /// order_id: pedido propietario y frontera de concurrencia.
  TextColumn get orderId =>
      text().references(SupplierOrders, #id, onDelete: KeyAction.restrict)();

  /// event_id: evento único que aplica documento, movimientos, balances y pedido.
  TextColumn get eventId => text()();

  /// intent_hash: SHA-256 canónico de la intención para detectar reutilización de identidad.
  TextColumn get intentHash => text()();

  /// base_event_id: último evento del pedido observado al recibir.
  TextColumn get baseEventId => text()();

  /// Fecha informada UTC en milisegundos; no arbitra concurrencia.
  IntColumn get occurredAtMs => integer()();

  /// Suma exacta de los importes reales de esta recepción, sin pagos contables.
  IntColumn get totalMinor => integer()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK (typeof(occurred_at_ms) = 'integer' AND occurred_at_ms BETWEEN 1 AND 9007199254740991)",
    "CHECK (typeof(total_minor) = 'integer' AND total_minor BETWEEN 0 AND 9007199254740991)",
    "UNIQUE (event_id)",
    "UNIQUE (order_id, id)",
    "CHECK (length(intent_hash) = 64)",
  ];
}
