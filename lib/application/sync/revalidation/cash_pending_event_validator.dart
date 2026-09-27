import '../models/sync_event.dart';
import '../payloads/caja_abierta_payload.dart';
import '../payloads/caja_cerrada_payload.dart';
import '../projections/cash_projection_store.dart';
import '../synced_event_history.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';

class CashPendingEventValidator implements PendingEventValidator {
  CashPendingEventValidator(this.history, this.store);
  final SyncedEventHistory history;
  final CashProjectionStore? store;
  @override
  Future<PendingConflict?> validate(
    SyncEvent e,
    Set<String> conflictedEventIds,
  ) async {
    final dependencies = e.eventType == CajaAbiertaPayload.eventType
        ? CajaAbiertaPayload.fromJson(e.payload).dependencyEventIds
        : CajaCerradaPayload.fromJson(e.payload).dependencyEventIds;
    for (final id in dependencies) {
      final d = await history.eventById(id);
      if (d == null ||
          conflictedEventIds.contains(id) ||
          ['conflict', 'rejected', 'not_required'].contains(d.deliveryStatus)) {
        return const PendingConflict(
          'Caja conservada localmente: una dependencia no se puede sincronizar. Requiere revisión.',
        );
      }
    }
    final session = await store?.find(e.aggregateId);
    if (session != null &&
        ((e.eventType == CajaAbiertaPayload.eventType &&
                session.createdEventId != e.eventId) ||
            session.deviceId != e.deviceId)) {
      return const PendingConflict(
        'Identidad o dispositivo de la caja en conflicto.',
      );
    }
    return null;
  }

  // Un conflicto de entrega nunca reabre ni borra una caja o sus movimientos.
  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {}
}
