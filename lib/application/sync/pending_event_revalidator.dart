import 'models/pending_revalidation_report.dart';
import 'models/sync_event.dart';
import 'projections/espacio_projection_store.dart';
import 'sync_persistence.dart';

class PendingEventRevalidator {
  PendingEventRevalidator({
    required SyncPersistence syncPersistence,
    required EspacioProjectionStore espacioProjectionStore,
  }) : _syncPersistence = syncPersistence,
       _espacioProjectionStore = espacioProjectionStore;

  final SyncPersistence _syncPersistence;
  final EspacioProjectionStore _espacioProjectionStore;

  Future<PendingRevalidationReport> revalidatePendingEvents() async {
    final events = await _syncPersistence.pendingEvents();
    var conflicts = 0;

    for (final event in events) {
      final conflictReason = switch (event.eventType) {
        'espacio_creado' => await _espacioCreadoConflictReason(event),
        _ => null,
      };

      if (conflictReason == null) continue;

      await _syncPersistence.updateEventSyncStatus(
        event.eventId,
        'conflict',
        rejectionReason: conflictReason,
      );
      await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
      conflicts++;
    }

    return PendingRevalidationReport(
      checked: events.length,
      conflicts: conflicts,
    );
  }

  Future<String?> _espacioCreadoConflictReason(SyncEvent event) async {
    final existingById = await _espacioProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return 'Ya existe un espacio oficial con id ${event.aggregateId}.';
    }

    final identificacion = _readOptionalText(event.payload['identificacion']);
    if (identificacion == null) return null;

    final existingByIdentificacion = await _espacioProjectionStore
        .findByIdentificacion(identificacion);

    if (existingByIdentificacion != null &&
        existingByIdentificacion.createdEventId != event.eventId) {
      return 'Ya existe un espacio oficial con identificacion $identificacion.';
    }

    return null;
  }

  String? _readOptionalText(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}
