import 'cash_event_handler.dart';
import '../models/sync_event.dart';
import '../payloads/abono_cliente_registrado_payload.dart';
import '../payloads/inventory_movement_payload.dart';
import '../projections/customer_credit_store.dart';

class AbonoClienteEventHandler {
  AbonoClienteEventHandler(this.store, {this.cash});
  final CashEventHandler? cash;
  final CustomerCreditStore store;
  Future<void> apply(SyncEvent event) async {
    InventoryMovementPayload.requiredUuidV4(event.aggregateId, 'abono_id');
    if (event.aggregateType != AbonoClienteRegistradoPayload.aggregateType ||
        event.eventType != AbonoClienteRegistradoPayload.eventType ||
        event.baseVersion != 1 ||
        event.baseServerSequence != null) {
      throw const FormatException('Sobre de abono inválido.');
    }
    final payload = AbonoClienteRegistradoPayload.fromJson(event.payload);
    await store.applyPayment(event, payload);
    if (payload.cash != null) {
      if (cash == null) throw StateError('Falta el receptor de caja.');
      await cash!.record(
        event,
        payload.cash,
        sourceType: 'customer_payment',
        sourceId: event.aggregateId,
        amountMinor: payload.amountMinor,
      );
    }
  }
}
