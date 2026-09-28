import '../models/sync_event.dart';
import '../payloads/inventory_movement_payload.dart';
import '../payloads/saldo_cuenta_inicial_declarado_payload.dart';
import '../projections/account_balance_baseline_projection_store.dart';

/// Handler idempotente de `saldo_cuenta_inicial_declarado`.
///
/// Reaplicar el mismo evento (eco del servidor) solo avanza
/// `last_server_sequence`. Si el slot único ya está ocupado —por esta o por
/// otra terminal— lanza `StateError` y el `appendAndApply` revierte en la misma
/// transacción: la fila del perdedor no queda a medias.
///
/// No hay `verify()` contra un conjunto de movimientos: el hecho no tiene
/// conjunto que verificar. No compara contra un cierre previo: no existe
/// `previous_close_event_id` porque no hay nada previo.
class AccountBalanceBaselineEventHandler {
  AccountBalanceBaselineEventHandler(this.store);
  final AccountBalanceBaselineProjectionStore store;

  Future<void> apply(SyncEvent e) => store.atomic(() async {
    InventoryMovementPayload.requiredUuidV4(e.aggregateId, 'baseline_id');
    if (e.aggregateType != SaldoCuentaInicialDeclaradoPayload.aggregateType ||
        e.eventType != SaldoCuentaInicialDeclaradoPayload.eventType ||
        e.baseVersion != 1 ||
        e.baseServerSequence != null) {
      throw const FormatException('Sobre de saldo inicial inválido.');
    }
    final baseline = await store.find(e.aggregateId);
    if (baseline?.createdEventId == e.eventId) {
      if (e.serverSequence != null) {
        await store.acknowledge(e.eventId, e.serverSequence!);
      }
      return;
    }
    if (baseline != null || await store.only() != null) {
      throw StateError('El saldo inicial ya fue declarado y es inmutable.');
    }
    await store.insertBaseline(
      e,
      SaldoCuentaInicialDeclaradoPayload.fromJson(e.payload),
    );
  });
}
