/// Catálogo y saldo conocidos; una fila por pareja variante/proveedor.
class ReplenishmentCandidate {
  const ReplenishmentCandidate({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.inventoryItemId,
    required this.unitId,
    required this.unitCode,
    required this.unitSymbol,
    required this.dimension,
    required this.atomicFactor,
    required this.referenceAtomic,
    required this.supplierId,
    required this.supplierName,
    required this.supplierPhone,
    required this.currentSupplierId,
    required this.targetAtomic,
    required this.balanceAtomic,
    required this.pendingAtomic,
    required this.priceMinor,
    required this.basis,
  });
  final String productId,
      variantId,
      productName,
      inventoryItemId,
      unitId,
      unitCode,
      unitSymbol,
      dimension,
      supplierId,
      supplierName,
      basis;
  final String? variantName, supplierPhone, currentSupplierId;
  final int atomicFactor,
      referenceAtomic,
      balanceAtomic,
      pendingAtomic,
      priceMinor;
  final int? targetAtomic;
  bool get isCurrent => supplierId == currentSupplierId;
  int get suggestedAtomic {
    final target = targetAtomic;
    if (target == null) return 0;
    final result =
        BigInt.from(target) -
        BigInt.from(balanceAtomic) -
        BigInt.from(pendingAtomic);
    if (result > BigInt.from(9007199254740991)) {
      throw StateError(
        'La sugerencia excede el límite de cantidad; revisa el saldo.',
      );
    }
    return result.isNegative ? 0 : result.toInt();
  }
}
