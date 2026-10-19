/// La alerta deriva del saldo físico vigente; el umbral puede quedar dormido.
class MinimumStockPolicy {
  const MinimumStockPolicy();

  bool isLow({
    required int? minimumStockAtomic,
    required int quantityOnHandAtomic,
    required bool productActive,
    required bool variantActive,
    required bool hasDirectTracking,
    required bool inventoryItemActive,
  }) =>
      minimumStockAtomic != null &&
      productActive &&
      variantActive &&
      hasDirectTracking &&
      inventoryItemActive &&
      quantityOnHandAtomic <= minimumStockAtomic;
}
