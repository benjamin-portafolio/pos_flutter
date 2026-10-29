import '../models/sync_event.dart';
import '../sale_adjustment_sync_contract.dart';
import '../synced_event_history.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';

class SaleAdjustmentPendingEventValidator implements PendingEventValidator {
  SaleAdjustmentPendingEventValidator(this.history);
  final SyncedEventHistory history;
  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    final deps = SaleAdjustmentSyncContract.dependencies(event);
    final base = await SaleAdjustmentSyncContract.resolve(event, history);
    if (base['status'] == 'incident' || deps.any(conflictedEventIds.contains)) {
      return const PendingConflict(
        'Operación física conservada: dependencia con incidencia. Requiere conciliación.',
      );
    }
    if (base['status'] == 'pending') return null;
    final official = await history.eventsForAggregateAfter(
      aggregateType: event.aggregateType,
      aggregateId: event.aggregateId,
      serverSequence: base['base_server_sequence'] as int,
    );
    if (official.any(
      (e) =>
          e.eventId != event.eventId &&
          SaleAdjustmentSyncContract.isCommercial(e.eventType) &&
          !deps.contains(e.eventId),
    )) {
      return const PendingConflict(
        'Otra operación oficial cambió la revisión; evidencia conservada.',
      );
    }
    return null;
  }

  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {} // Nunca deshacer dinero/mercancía.
}
