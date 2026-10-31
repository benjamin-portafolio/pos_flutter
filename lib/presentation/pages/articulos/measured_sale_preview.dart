import '../../../application/sync/payloads/sale_item_snapshot.dart';
import '../../../domain/ventas/measured_sale_conditions.dart';
import '../../../domain/ventas/sale_draft.dart';

/// Usa las mismas condiciones y el mismo redondeo que la acumulación del comando.
class MeasuredSalePreview {
  const MeasuredSalePreview();

  SaleItemSnapshot capture(MeasuredSaleConditions conditions, int atomic) =>
      SaleItemSnapshot(
        variantId: conditions.variantId,
        priceSnapshotVersion: conditions.priceSnapshotVersion,
        normalPriceMinorSnapshot: conditions.normalPriceMinorSnapshot,
        offerPriceMinorSnapshot: conditions.offerPriceMinorSnapshot,
        effectivePriceSource: conditions.effectivePriceSource,
        priceSelection: conditions.priceSnapshotVersion == 2 ? 'inherit' : null,
        priceConfigurationEventId: conditions.priceConfigurationEventId,
        productName: conditions.productName,
        variantName: conditions.variantName,
        saleMode: 'measured',
        quantity: null,
        measuredQuantityAtomic: atomic,
        unitPriceMinor: conditions.unitPriceMinor,
        standardCostMinor: conditions.standardCostMinor,
        consumptionConfigurationKey: conditions.consumptionConfigurationKey,
        priceReferenceQuantityAtomic: conditions.priceReferenceQuantityAtomic,
        unitCode: conditions.unit.code,
        unitSymbol: conditions.unit.simbolo,
        unitAtomicFactor: conditions.unit.factorAtomico,
      );

  SaleItemSnapshot? accumulated(SaleItemSnapshot capture, SaleDraft? draft) {
    for (final item in draft?.items ?? []) {
      final existing = SaleItemSnapshot(
        variantId: item.variantId,
        priceSnapshotVersion: item.priceSnapshotVersion,
        normalPriceMinorSnapshot: item.normalPriceMinorSnapshot,
        offerPriceMinorSnapshot: item.offerPriceMinorSnapshot,
        effectivePriceSource: item.effectivePriceSource,
        priceSelection: item.priceSelection,
        priceConfigurationEventId: item.priceConfigurationEventId,
        consumptionConfigurationKey: item.consumptionConfigurationKey,
        productName: item.productName,
        variantName: item.variantName,
        saleMode: item.quantity == null ? 'measured' : 'unit',
        quantity: item.quantity,
        measuredQuantityAtomic: item.measuredQuantityAtomic,
        unitPriceMinor: item.unitPriceMinor,
        standardCostMinor: item.standardCostMinor,
        priceReferenceQuantityAtomic: item.priceReferenceQuantityAtomic,
        unitCode: item.unitCode,
        unitSymbol: item.unitSymbol,
        unitAtomicFactor: item.unitAtomicFactor,
      );
      if (existing.sameConditions(capture)) return existing.plus(capture);
    }
    return null;
  }
}
