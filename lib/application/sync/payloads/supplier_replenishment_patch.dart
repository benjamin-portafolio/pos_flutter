import 'supplier_order_json.dart';

/// Ausencia conserva, null retira, valor establece.
class SupplierReplenishmentPatch {
  const SupplierReplenishmentPatch._(
    this.hasSupplier,
    this.supplierId,
    this.hasTarget,
    this.targetAtomic,
  );
  const SupplierReplenishmentPatch.preserve()
    : hasSupplier = false,
      supplierId = null,
      hasTarget = false,
      targetAtomic = null;
  factory SupplierReplenishmentPatch.values({
    required String? supplierId,
    required int? targetAtomic,
  }) => SupplierReplenishmentPatch.fromJson({
    'current_supplier_id': supplierId,
    'target_stock_atomic': targetAtomic,
  });
  final bool hasSupplier, hasTarget;
  final String? supplierId;
  final int? targetAtomic;
  factory SupplierReplenishmentPatch.fromJson(Object? value) {
    final j = orderRecord(value);
    return SupplierReplenishmentPatch._(
      j.containsKey('current_supplier_id'),
      j['current_supplier_id'] == null
          ? null
          : orderUuid(j['current_supplier_id']),
      j.containsKey('target_stock_atomic'),
      j['target_stock_atomic'] == null
          ? null
          : orderInt(j['target_stock_atomic']),
    );
  }
  Map<String, Object?> toJson() => {
    if (hasSupplier) 'current_supplier_id': supplierId,
    if (hasTarget) 'target_stock_atomic': targetAtomic,
  };
}
