import '../models/sync_event.dart';
import '../payloads/venta_confirmada_payload.dart';

abstract interface class ConfirmedSaleStore {
  Future<void> apply(SyncEvent event, VentaConfirmadaPayload payload);
  Future<void> acknowledge(String eventId, int serverSequence);
  Stream<List<SyncEvent>> watchConfirmed();
}
