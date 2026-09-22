import '../models/sync_event.dart';
import '../payloads/abono_cliente_registrado_payload.dart';
import '../payloads/inventory_movement_payload.dart';
import '../projections/customer_credit_store.dart';

class AbonoClienteEventHandler {
  AbonoClienteEventHandler(this.store);
  final CustomerCreditStore store;
  Future<void> apply(SyncEvent event) async {
    InventoryMovementPayload.requiredUuidV4(event.aggregateId, 'abono_id');
    if (event.aggregateType != AbonoClienteRegistradoPayload.aggregateType ||
        event.eventType != AbonoClienteRegistradoPayload.eventType ||
        event.baseVersion != 1 ||
        event.baseServerSequence != null) {
      throw const FormatException('Sobre de abono inválido.');
    }
    await store.applyPayment(
      event,
      AbonoClienteRegistradoPayload.fromJson(event.payload),
    );
  }
}
