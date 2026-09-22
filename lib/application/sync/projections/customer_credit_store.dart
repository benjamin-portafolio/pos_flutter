import '../models/sync_event.dart';
import '../payloads/abono_cliente_registrado_payload.dart';

abstract interface class CustomerCreditStore {
  Future<T> atomic<T>(Future<T> Function() action);
  Future<SyncEvent?> paymentEvent(String id);
  Future<void> applyPayment(
    SyncEvent event,
    AbonoClienteRegistradoPayload payload,
  );
  Future<void> acknowledge(String eventId, int serverSequence);
}
