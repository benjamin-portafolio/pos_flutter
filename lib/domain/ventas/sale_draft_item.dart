/// Línea de lectura con las condiciones guardadas al capturar la venta.
class SaleDraftItem {
  const SaleDraftItem({
    required this.id,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.measuredQuantityAtomic,
    required this.unitPriceMinor,
    required this.priceReferenceQuantityAtomic,
    required this.unitCode,
    required this.unitSymbol,
    required this.unitAtomicFactor,
    required this.totalMinor,
  });

  final String id;
  final String variantId;
  final String productName;
  final String? variantName;
  final int? quantity;
  final int? measuredQuantityAtomic;
  final int unitPriceMinor;
  final int? priceReferenceQuantityAtomic;
  final String? unitCode;
  final String? unitSymbol;
  final int? unitAtomicFactor;
  final int totalMinor;
}
