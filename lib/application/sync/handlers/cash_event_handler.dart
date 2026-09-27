import '../models/sync_event.dart';
import '../payloads/caja_abierta_payload.dart';
import '../payloads/caja_cerrada_payload.dart';
import '../payloads/cash_binding_payload.dart';
import '../payloads/cash_movement_evidence.dart';
import '../payloads/inventory_movement_payload.dart';
import '../projections/cash_projection_store.dart';

class CashEventHandler {
  CashEventHandler(this.store);
  final CashProjectionStore store;
  Future<void> apply(SyncEvent e) => store.atomic(() async {
    InventoryMovementPayload.requiredUuidV4(e.aggregateId, 'session_id');
    if (e.aggregateType != CajaAbiertaPayload.aggregateType ||
        e.baseVersion != 1 ||
        e.baseServerSequence != null) {
      throw const FormatException('Sobre de caja inválido.');
    }
    final session = await store.find(e.aggregateId);
    if (e.eventType == CajaAbiertaPayload.eventType) {
      final p = CajaAbiertaPayload.fromJson(e.payload);
      if (session?.createdEventId == e.eventId) {
        if (e.serverSequence != null) {
          await store.acknowledge(e.eventId, e.serverSequence!);
        }
        return;
      }
      if (session != null || await store.current(e.deviceId) != null) {
        throw StateError(
          'Ya existe una sesión abierta o esta identidad fue utilizada.',
        );
      }
      final previous = await store.latest(e.deviceId);
      if (previous?.lastEventId != p.previousCloseEventId) {
        throw StateError(
          'La apertura no depende del último cierre del dispositivo.',
        );
      }
      await store.insertSession(e, p);
      return;
    }
    if (e.eventType != CajaCerradaPayload.eventType) {
      throw const FormatException('Evento de caja inválido.');
    }
    final p = CajaCerradaPayload.fromJson(e.payload);
    if (session?.lastEventId == e.eventId) {
      if (e.serverSequence != null) {
        await store.acknowledge(e.eventId, e.serverSequence!);
      }
      return;
    }
    if (session == null ||
        session.status != 'open' ||
        session.deviceId != e.deviceId ||
        session.createdEventId != p.openingEventId) {
      throw StateError(
        'La sesión no está abierta o pertenece a otro dispositivo.',
      );
    }
    p.verify(session.openingMinor, await store.movements(session.id));
    await store.closeSession(e, p);
  });

  /// Invocado dentro de la misma transacción que persiste el origen real.
  Future<void> record(
    SyncEvent e,
    CashBindingPayload? binding, {
    required String sourceType,
    required String sourceId,
    required int amountMinor,
    String direction = 'in',
  }) async {
    if (binding == null) return;
    final evidence = CashMovementEvidence(
      movementId: binding.movementId,
      eventId: e.eventId,
      direction: direction,
      amountMinor: amountMinor,
      sourceType: sourceType,
      sourceId: sourceId,
    );
    final existing = (await store.movements(
      binding.sessionId,
    )).where((m) => m.movementId == binding.movementId);
    if (existing.isNotEmpty && existing.single.eventId == e.eventId) return;
    final session = await store.find(binding.sessionId);
    if (session == null ||
        session.status != 'open' ||
        session.deviceId != e.deviceId ||
        session.createdEventId != binding.openingEventId) {
      throw StateError(
        'Abre una caja de esta terminal antes de registrar efectivo.',
      );
    }
    await store.insertMovement(e, binding, evidence);
  }
}
