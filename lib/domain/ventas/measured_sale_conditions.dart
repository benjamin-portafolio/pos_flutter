import '../inventario/unidad_inventario.dart';

/// Condiciones actuales del catálogo necesarias para anticipar una línea medida.
class MeasuredSaleConditions {
  const MeasuredSaleConditions({
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.unit,
    required this.unitPriceMinor,
    required this.priceReferenceQuantityAtomic,
    required this.standardCostMinor,
    required this.consumptionConfigurationKey,
  });

  final String variantId;
  final String productName;
  final String? variantName;
  final UnidadInventario unit;
  final int unitPriceMinor;
  final int priceReferenceQuantityAtomic;
  final int? standardCostMinor;
  final String consumptionConfigurationKey;
}
