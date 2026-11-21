import '../../sync/payloads/supplier_order_json.dart';

/// Capture intent before filtering unreceived lines. IDs stay stable across retries.
class SupplierReceiptInputLine {
  const SupplierReceiptInputLine({
    required this.orderItemId,
    required this.movementId,
    required this.quantityAtomic,
    required this.actualPriceMinor,
    required this.referenceQuantityAtomic,
    this.overageAcknowledged = false,
  });
  final String orderItemId, movementId;
  final int quantityAtomic, actualPriceMinor, referenceQuantityAtomic;
  final bool overageAcknowledged;
  Map<String, Object?> validatedJson() {
    orderUuid(orderItemId);
    orderUuid(movementId);
    orderInt(quantityAtomic);
    orderInt(actualPriceMinor);
    orderInt(referenceQuantityAtomic, 1);
    return {
      'order_item_id': orderItemId,
      'movement_id': movementId,
      'quantity_atomic': quantityAtomic,
      'actual_price_minor': actualPriceMinor,
      'reference_quantity_atomic': referenceQuantityAtomic,
      'total_minor': quantityAtomic == 0
          ? 0
          : orderAmount(
              actualPriceMinor,
              quantityAtomic,
              referenceQuantityAtomic,
            ),
      'overage_acknowledged': overageAcknowledged,
    };
  }
}
