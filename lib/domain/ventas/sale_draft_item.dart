/// Línea de lectura con las condiciones guardadas al capturar la venta.
class SaleDraftItem {
  const SaleDraftItem({
    this.priceSnapshotVersion,
    this.normalPriceMinorSnapshot,
    this.offerPriceMinorSnapshot,
    this.effectivePriceSource,
    this.priceSelection,
    this.priceConfigurationEventId,
    required this.id,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.measuredQuantityAtomic,
    required this.unitPriceMinor,
    this.standardCostMinor,
    this.consumptionConfigurationKey,
    required this.priceReferenceQuantityAtomic,
    required this.unitCode,
    required this.unitSymbol,
    required this.unitAtomicFactor,
    required this.totalMinor,
  });

  final int? priceSnapshotVersion,
      normalPriceMinorSnapshot,
      offerPriceMinorSnapshot;
  final String? effectivePriceSource, priceSelection, priceConfigurationEventId;
  String get effectivePriceOrigin => effectivePriceSource ?? 'unknown';
  final String id;
  final String variantId;

  /// Configuración de consumo capturada; participa en la agrupación de líneas.
  /// Null conserva la ausencia explícita en snapshots legados.
  final String? consumptionConfigurationKey;
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
