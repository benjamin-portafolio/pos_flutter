import 'supplier_order_json.dart';

/// Contrato v1 compartido por comandos, recepción y recuperación.
class SupplierReceiptLine {
  SupplierReceiptLine._(
    this.orderItemId,
    this.movementId,
    this.quantityAtomic,
    this.actualPriceMinor,
    this.referenceQuantityAtomic,
    this.totalMinor,
    this.overageAcknowledged,
  );
  final String orderItemId;
  final String movementId;
  final int quantityAtomic;
  final int actualPriceMinor;
  final int referenceQuantityAtomic;
  final int totalMinor;
  final bool overageAcknowledged;
  factory SupplierReceiptLine.fromJson(Object? value) {
    final j = orderRecord(value);
    final p = SupplierReceiptLine._(
      orderUuid(j['order_item_id']),
      orderUuid(j['movement_id']),
      orderInt(j['quantity_atomic'], 1),
      orderInt(j['actual_price_minor']),
      orderInt(j['reference_quantity_atomic'], 1),
      orderInt(j['total_minor']),
      j['overage_acknowledged'] is bool
          ? j['overage_acknowledged'] as bool
          : throw const FormatException('Booleano requerido'),
    );
    if (p.totalMinor !=
        orderAmount(
          p.actualPriceMinor,
          p.quantityAtomic,
          p.referenceQuantityAtomic,
        )) {
      throw const FormatException('Importe incoherente');
    }
    return p;
  }
  Map<String, Object?> toJson() => {
    'order_item_id': orderItemId,
    'movement_id': movementId,
    'quantity_atomic': quantityAtomic,
    'actual_price_minor': actualPriceMinor,
    'reference_quantity_atomic': referenceQuantityAtomic,
    'total_minor': totalMinor,
    'overage_acknowledged': overageAcknowledged,
  };
}
