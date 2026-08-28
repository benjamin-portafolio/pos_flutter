class InventoryAdjustmentFormResult {
  const InventoryAdjustmentFormResult({
    required this.quantityDeltaAtomic,
    required this.reason,
  });

  final int quantityDeltaAtomic;
  final String reason;
}
