/// Selección emitida de una línea; conserva cantidad/unidad y nombres originales.
class QuotationItem {
  const QuotationItem({
    required this.id,
    required this.sortOrder,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.saleMode,
    required this.quantity,
    required this.measuredQuantityAtomic,
    required this.unitCode,
    required this.unitSymbol,
    required this.unitAtomicFactor,
  });

  final String id, variantId, productName, saleMode;
  final String? variantName, unitCode, unitSymbol;
  final int sortOrder;
  final int? quantity, measuredQuantityAtomic;
  final int? unitAtomicFactor;
}
