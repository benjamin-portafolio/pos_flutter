import 'sale_adjustment_json.dart';

class SaleAdjustmentStock {
  SaleAdjustmentStock._(
    this.movementId,
    this.originalMovementId,
    this.inventoryItemId,
    this.quantityAtomic,
  );
  final String movementId;
  final String originalMovementId;
  final String inventoryItemId;
  final int quantityAtomic;
  factory SaleAdjustmentStock.fromJson(Object? value) {
    final j = adjustmentObject(value, [
      'movement_id',
      'original_movement_id',
      'inventory_item_id',
      'quantity_atomic',
    ]);
    return SaleAdjustmentStock._(
      adjustmentId(j['movement_id']),
      adjustmentId(j['original_movement_id']),
      adjustmentId(j['inventory_item_id']),
      adjustmentInt(j['quantity_atomic'], 1),
    );
  }
  Map<String, Object?> toJson() => {
    'movement_id': movementId,
    'original_movement_id': originalMovementId,
    'inventory_item_id': inventoryItemId,
    'quantity_atomic': quantityAtomic,
  };
}
