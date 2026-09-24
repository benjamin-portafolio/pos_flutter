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
    this.standardCostMinor,
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

  /// Costo estándar capturado al agregar la línea, en centavos.
  /// `null` significa costo desconocido; `0` es un costo conocido válido.
  /// Los cambios posteriores del catálogo no reescriben este snapshot.
  final int? standardCostMinor;
}
