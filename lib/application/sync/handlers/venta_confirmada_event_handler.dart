import '../models/sync_event.dart';
import '../payloads/venta_confirmada_payload.dart';
import '../projections/confirmed_sale_store.dart';

class VentaConfirmadaEventHandler {
  VentaConfirmadaEventHandler(this.store);
  final ConfirmedSaleStore store;
  Future<void> apply(SyncEvent event) async {
    if (event.aggregateType != VentaConfirmadaPayload.aggregateType ||
        event.eventType != VentaConfirmadaPayload.eventType ||
        event.baseVersion != 1 ||
        event.baseServerSequence != null) {
      throw const FormatException('Sobre de venta inválido.');
    }
    await store.apply(event, VentaConfirmadaPayload.fromJson(event.payload));
  }
}
