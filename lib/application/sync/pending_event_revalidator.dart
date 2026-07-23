import 'models/pending_revalidation_report.dart';
import 'models/sync_event.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/espacio_creado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/espacio_projection_store.dart';
import 'sync_persistence.dart';

class PendingEventRevalidator {
  PendingEventRevalidator({
    required SyncPersistence syncPersistence,
    required EspacioProjectionStore espacioProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
  }) : _syncPersistence = syncPersistence,
       _espacioProjectionStore = espacioProjectionStore,
       _categoriaProjectionStore = categoriaProjectionStore;

  final SyncPersistence _syncPersistence;
  final EspacioProjectionStore _espacioProjectionStore;
  final CategoriaProjectionStore _categoriaProjectionStore;

  Future<PendingRevalidationReport> revalidatePendingEvents() async {
    final events = await _syncPersistence.pendingEvents();
    var conflicts = 0;

    for (final event in events) {
      final conflictReason = switch (event.eventType) {
        EspacioCreadoPayload.eventType => await _espacioCreadoConflictReason(
          event,
        ),
        CategoriaCreadaPayload.eventType =>
          await _categoriaCreadaConflictReason(event),
        _ => null,
      };

      if (conflictReason == null) continue;

      await _syncPersistence.updateEventSyncStatus(
        event.eventId,
        'conflict',
        rejectionReason: conflictReason,
      );
      await _deleteCreatedProjection(event);
      conflicts++;
    }

    return PendingRevalidationReport(
      checked: events.length,
      conflicts: conflicts,
    );
  }

  Future<String?> _categoriaCreadaConflictReason(SyncEvent event) async {
    final existingById = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return 'Ya existe una categoría oficial con id ${event.aggregateId}.';
    }
    return null;
  }

  Future<void> _deleteCreatedProjection(SyncEvent event) async {
    switch (event.eventType) {
      case EspacioCreadoPayload.eventType:
        await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
      case CategoriaCreadaPayload.eventType:
        await _categoriaProjectionStore.deleteCreatedByEvent(event.eventId);
    }
  }

  Future<String?> _espacioCreadoConflictReason(SyncEvent event) async {
    final existingById = await _espacioProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return 'Ya existe un espacio oficial con id ${event.aggregateId}.';
    }

    final payload = EspacioCreadoPayload.fromJson(event.payload);
    final identificacion = payload.identificacion;
    if (identificacion == null) return null;

    final existingByIdentificacion = await _espacioProjectionStore
        .findByIdentificacion(identificacion);

    if (existingByIdentificacion != null &&
        existingByIdentificacion.createdEventId != event.eventId) {
      return 'Ya existe un espacio oficial con identificacion $identificacion.';
    }

    return null;
  }
}
