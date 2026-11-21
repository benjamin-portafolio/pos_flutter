import 'supplier_order_json.dart';

/// Contrato v1 compartido por comandos, recepción y recuperación.
class SupplierClosedLine {
  SupplierClosedLine._(this.orderItemId, this.closedQuantityAtomic);
  final String orderItemId;
  final int closedQuantityAtomic;
  factory SupplierClosedLine.fromJson(Object? value) {
    final j = orderRecord(value);
    final p = SupplierClosedLine._(
      orderUuid(j['order_item_id']),
      orderInt(j['closed_quantity_atomic'], 1),
    );
    return p;
  }
  Map<String, Object?> toJson() => {
    'order_item_id': orderItemId,
    'closed_quantity_atomic': closedQuantityAtomic,
  };
}
