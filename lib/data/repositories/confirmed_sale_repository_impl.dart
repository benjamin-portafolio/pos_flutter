import '../../application/sync/projections/confirmed_sale_store.dart';
import '../../application/sync/payloads/venta_confirmada_payload.dart';
import '../../domain/repositories/confirmed_sale_repository.dart';
import '../../domain/ventas/confirmed_sale.dart';
import '../../domain/ventas/sale_draft_item.dart';

class ConfirmedSaleRepositoryImpl implements ConfirmedSaleRepository {
  ConfirmedSaleRepositoryImpl(this.store);
  final ConfirmedSaleStore store;
  @override
  Stream<List<ConfirmedSale>> watchSales() => store.watchConfirmed().map(
    (events) => events.map((e) {
      final p = VentaConfirmadaPayload.fromJson(e.payload);
      return ConfirmedSale(
        id: e.aggregateId,
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
              productName: l.snapshot.productName,
              variantName: l.snapshot.variantName,
              quantity: l.snapshot.quantity,
              measuredQuantityAtomic: l.snapshot.measuredQuantityAtomic,
              unitPriceMinor: l.snapshot.unitPriceMinor,
              priceReferenceQuantityAtomic:
                  l.snapshot.priceReferenceQuantityAtomic,
              unitCode: l.snapshot.unitCode,
              unitSymbol: l.snapshot.unitSymbol,
              unitAtomicFactor: l.snapshot.unitAtomicFactor,
              totalMinor: l.snapshot.totalMinor,
            ),
        ],
      );
    }).toList(),
  );
}
