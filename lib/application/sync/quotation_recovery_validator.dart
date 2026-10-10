import '../../domain/inventario/dimension_unidad.dart';
import '../../domain/inventario/inventory_consumption_configuration.dart';
import '../../domain/articulos/sale_configuration.dart';
import '../../domain/repositories/unidad_inventario_repository.dart';
import 'payloads/sale_item_snapshot.dart';
import 'prepared_quotation_line.dart';
import 'projections/producto_projection_store.dart';
import 'projections/quotation_item_projection.dart';
import 'quotation_recovery_line_exception.dart';

/// Resuelve catálogo local bajo la transacción de su consumidor, sin escrituras.
class QuotationRecoveryValidator {
  QuotationRecoveryValidator({required this.products, required this.units});
  final ProductoProjectionStore products;
  final UnidadInventarioRepository units;
  Future<List<PreparedQuotationLine>> prepare({
    required List<QuotationItemProjection> items,
  }) async {
    if (items.isEmpty) throw StateError('La cotización no tiene líneas.');
    final result = <PreparedQuotationLine>[];
    var total = BigInt.zero;
    for (final item in items) {
      final line = await prepareLine(item);
      total += BigInt.from(line.snapshot.totalMinor);
      if (total > BigInt.from(SaleItemSnapshot.maxInteger)) {
        throw const FormatException('El total excede el límite permitido.');
      }
      result.add(line);
    }
    return result;
  }

  Future<PreparedQuotationLine> prepareLine(
    QuotationItemProjection item,
  ) async {
    Never invalid(String reason) =>
        throw QuotationRecoveryLineException(item.id, reason);
    if (!item.active) invalid('La línea guardada no está activa.');
    final s = item.selection;
    final variant = await products.findVariantById(s.variantId);
    if (variant == null || !variant.active) {
      invalid('La variante ya no está disponible.');
    }
    final product = await products.findProductById(variant.productoId);
    if (product == null || !product.active) {
      invalid('El artículo ya no está disponible.');
    }
    final config = product.saleConfiguration;
    if ((config is MeasuredSaleConfiguration) != (s.saleMode == 'measured')) {
      invalid('Cambió el modo de venta.');
    }
    final unit = config is MeasuredSaleConfiguration
        ? await units.obtenerUnidadPorId(config.saleUnitId)
        : null;
    final dimension = switch (s.unitCode) {
      'g' || 'kg' => DimensionUnidad.mass,
      'ml' || 'l' => DimensionUnidad.volume,
      _ => null,
    };
    if (config is MeasuredSaleConfiguration &&
        (unit == null ||
            !unit.activa ||
            unit.code != s.unitCode ||
            unit.dimension != dimension ||
            unit.simbolo != s.unitSymbol ||
            unit.factorAtomico != s.unitAtomicFactor)) {
      invalid('La unidad está ausente, inactiva o cambió su interpretación.');
    }
    try {
      final consumption = await products.consumptionConfigurationKey(
        variant.id,
      );
      InventoryConsumptionConfiguration.fromKey(consumption);
      final snapshot = SaleItemSnapshot(
        variantId: variant.id,
        consumptionConfigurationKey: consumption,
        productName: product.nombre,
        variantName: variant.nombre,
        saleMode: s.saleMode,
        quantity: s.quantity,
        measuredQuantityAtomic: s.measuredQuantityAtomic,
        unitPriceMinor: variant.precioVentaMenor,
        standardCostMinor: variant.costoEstandarMenor,
        priceReferenceQuantityAtomic: config.priceReferenceQuantityAtomic,
        unitCode: unit?.code,
        unitSymbol: unit?.simbolo,
        unitAtomicFactor: unit?.factorAtomico,
      );
      return PreparedQuotationLine(
        quotationItemId: item.id,
        productId: product.id,
        unitId: unit?.id,
        sortOrder: item.sortOrder,
        snapshot: snapshot,
      );
    } on FormatException {
      invalid('El precio, costo o configuración actuales no son válidos.');
    }
  }
}
