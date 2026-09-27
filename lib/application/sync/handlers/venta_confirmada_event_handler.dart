import 'cash_event_handler.dart';
import '../models/sync_event.dart';
import '../payloads/venta_confirmada_payload.dart';
import '../projections/confirmed_sale_store.dart';

class VentaConfirmadaEventHandler {
  VentaConfirmadaEventHandler(this.store, {this.cash});
  final CashEventHandler? cash;
  final ConfirmedSaleStore store;
  Future<void> apply(SyncEvent event) async {
    if (event.aggregateType != VentaConfirmadaPayload.aggregateType ||
        event.eventType != VentaConfirmadaPayload.eventType ||
        event.baseVersion != 1 ||
        event.baseServerSequence != null) {
      throw const FormatException('Sobre de venta inválido.');
    }
    final payload = VentaConfirmadaPayload.fromJson(event.payload);
    await store.apply(event, payload);
    if (payload.cash != null) {
      if (cash == null) throw StateError('Falta el receptor de caja.');
      await cash!.record(
        event,
        payload.cash,
        sourceType: 'sale_payment',
        sourceId: payload.paymentId!,
        amountMinor: payload.totalMinor,
      );
    }
  }
}
