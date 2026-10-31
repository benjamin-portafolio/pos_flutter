import '../../application/sync/models/sync_event.dart';
import '../../application/sync/projections/confirmed_sale_store.dart';
import '../../application/sync/payloads/venta_confirmada_payload.dart';
import '../../domain/repositories/confirmed_sale_repository.dart';
import '../../domain/ventas/confirmed_sale.dart';
import '../../domain/ventas/sale_draft_item.dart';
import '../../domain/repositories/sale_adjustment_repository.dart';

class ConfirmedSaleRepositoryImpl implements ConfirmedSaleRepository {
  ConfirmedSaleRepositoryImpl(this.store, {this.adjustments});
  final SaleAdjustmentRepository? adjustments;
  final ConfirmedSaleStore store;
  @override
  Stream<List<ConfirmedSale>> watchSales() =>
      adjustments?.watchSales().map(
        (sales) => sales.map((s) => s.original.withAdjustments(s)).toList(),
      ) ??
      store.watchConfirmed().map((events) => events.map(fromEvent).toList());

  static ConfirmedSale fromEvent(SyncEvent e) {
    final p = VentaConfirmadaPayload.fromJson(e.payload);
    return ConfirmedSale(
      id: e.aggregateId,
      pricingContractVersion: p.pricingContractVersion,
      pricingMode: p.pricingMode,
      paymentMethod: p.paymentMethod,
      paymentReference: p.paymentReference,
      clienteId: p.clienteId,
      clienteNombre: p.clienteNombre,
      createdAt: e.createdAtLocal,
      totalMinor: p.totalMinor,
      receivedMinor: p.receivedMinor,
      changeMinor: p.changeMinor,
      currency: p.currency,
      deliveryStatus: e.deliveryStatus,
      reason: e.rejectionReason,
      items: [
        for (final l in p.lines)
          SaleDraftItem(
            id: l.id,
            variantId: l.snapshot.variantId,
            priceSnapshotVersion: l.snapshot.priceSnapshotVersion,
            normalPriceMinorSnapshot: l.snapshot.normalPriceMinorSnapshot,
            offerPriceMinorSnapshot: l.snapshot.offerPriceMinorSnapshot,
            effectivePriceSource: l.snapshot.effectivePriceSource,
            priceSelection: l.snapshot.priceSelection,
            priceConfigurationEventId: l.snapshot.priceConfigurationEventId,
            consumptionConfigurationKey: l.snapshot.consumptionConfigurationKey,
            productName: l.snapshot.productName,
            variantName: l.snapshot.variantName,
            quantity: l.snapshot.quantity,
            measuredQuantityAtomic: l.snapshot.measuredQuantityAtomic,
            unitPriceMinor: l.snapshot.unitPriceMinor,
            standardCostMinor: l.snapshot.standardCostMinor,
            priceReferenceQuantityAtomic:
                l.snapshot.priceReferenceQuantityAtomic,
            unitCode: l.snapshot.unitCode,
            unitSymbol: l.snapshot.unitSymbol,
            unitAtomicFactor: l.snapshot.unitAtomicFactor,
            totalMinor: l.snapshot.totalMinor,
          ),
      ],
    );
  }
}
