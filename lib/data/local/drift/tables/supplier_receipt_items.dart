import 'package:drift/drift.dart';
import 'inventory_movements.dart';
import 'supplier_order_items.dart';
import 'supplier_orders.dart';
import 'supplier_receipts.dart';

/// Hijo del pedido; sin versión propia. La base del pedido serializa toda escritura.
@DataClassName('SupplierReceiptItemRow')
@TableIndex.sql(
  'CREATE INDEX ix_supplier_receipt_items_lookup ON supplier_receipt_items (order_item_id, receipt_id)',
)
class SupplierReceiptItems extends Table {
  /// Identidad UUID estable, independiente de la posición.
  TextColumn get id => text()();

  /// Recepción propietaria; la FK compuesta exige que pertenezca al pedido.
  TextColumn get receiptId =>
      text().references(SupplierReceipts, #id, onDelete: KeyAction.restrict)();

  /// order_id: pedido propietario y frontera de concurrencia.
  TextColumn get orderId =>
      text().references(SupplierOrders, #id, onDelete: KeyAction.restrict)();

  /// Partida original del pedido; la FK compuesta impide cruzar pedidos.
  TextColumn get orderItemId => text().references(
    SupplierOrderItems,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Cantidad positiva pedida o realmente recibida en átomos; nunca saldo absoluto.
  IntColumn get quantityAtomic => integer()();

  /// Precio real conocido en unidad menor; cero explícito válido.
  IntColumn get actualPriceMinor => integer()();

  /// Importe real redondeado de la cantidad recibida, en unidad monetaria menor.
  IntColumn get totalMinor => integer()();

  /// movement_id: movimiento positivo único; nunca otro evento de entrada.
  TextColumn get movementId => text().references(
    InventoryMovements,
    #movementId,
    onDelete: KeyAction.restrict,
  )();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    "CHECK (typeof(quantity_atomic) = 'integer' AND quantity_atomic BETWEEN 1 AND 9007199254740991)",
    "CHECK (typeof(actual_price_minor) = 'integer' AND actual_price_minor BETWEEN 0 AND 9007199254740991)",
    "CHECK (typeof(total_minor) = 'integer' AND total_minor BETWEEN 0 AND 9007199254740991)",
    "UNIQUE (movement_id)",
    "UNIQUE (receipt_id, order_item_id)",
    "FOREIGN KEY (order_id, receipt_id) REFERENCES supplier_receipts(order_id, id) ON DELETE RESTRICT",
    "FOREIGN KEY (order_id, order_item_id) REFERENCES supplier_order_items(order_id, id) ON DELETE RESTRICT",
  ];
}
