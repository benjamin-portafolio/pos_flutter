import 'categoria_conflict_projection_restorer.dart';
import 'models/pending_revalidation_report.dart';
import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/espacio_creado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/espacio_projection_store.dart';
import 'sync_persistence.dart';
import 'synced_event_history.dart';

class PendingEventRevalidator {
  PendingEventRevalidator({
    required SyncPersistence syncPersistence,
    required SyncedEventHistory syncedEventHistory,
    required EspacioProjectionStore espacioProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
    required CategoriaConflictProjectionRestorer
    categoriaConflictProjectionRestorer,
  }) : _syncPersistence = syncPersistence,
       _syncedEventHistory = syncedEventHistory,
       _espacioProjectionStore = espacioProjectionStore,
       _categoriaProjectionStore = categoriaProjectionStore,
       _categoriaConflictProjectionRestorer =
           categoriaConflictProjectionRestorer;

  final SyncPersistence _syncPersistence;
  final SyncedEventHistory _syncedEventHistory;
  final EspacioProjectionStore _espacioProjectionStore;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final CategoriaConflictProjectionRestorer
  _categoriaConflictProjectionRestorer;

  Future<PendingRevalidationReport> revalidatePendingEvents() async {
    final events = await _syncPersistence.pendingEvents();
    var conflicts = 0;

    for (final event in events) {
      final conflict = switch (event.eventType) {
        EspacioCreadoPayload.eventType => await _espacioCreadoConflict(event),
        CategoriaCreadaPayload.eventType => await _categoriaCreadaConflict(
          event,
        ),
        CategoriaActualizadaPayload.eventType =>
          await _categoriaActualizadaConflict(event),
        _ => null,
      };

      if (conflict == null) continue;

      await _syncPersistence.updateEventSyncStatus(
        event.eventId,
        'conflict',
        rejectionReason: conflict.reason,
      );
      await _hideConflictProjection(event, conflict);
      conflicts++;
    }

    return PendingRevalidationReport(
      checked: events.length,
      conflicts: conflicts,
    );
  }

  Future<_PendingConflict?> _categoriaCreadaConflict(SyncEvent event) async {
    final existingById = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return _PendingConflict(
        'Ya existe una categoría oficial con id ${event.aggregateId}.',
      );
    }
    return null;
  }

  Future<_PendingConflict?> _categoriaActualizadaConflict(
    SyncEvent event,
  ) async {
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existing == null) {
      return _PendingConflict(
        'Ya no existe la categoría que se intentó actualizar.',
      );
    }

    final baseServerSequence = event.baseServerSequence;
    if (baseServerSequence == null) return null;

    final payload = CategoriaActualizadaPayload.fromJson(event.payload);
    final officialEvents = await _syncedEventHistory.eventsForAggregateAfter(
      aggregateType: CategoriaActualizadaPayload.aggregateType,
      aggregateId: event.aggregateId,
      serverSequence: baseServerSequence,
    );
    final officialChangedFields = <String>{};
    for (final officialEvent in officialEvents) {
      if (officialEvent.eventId == event.eventId ||
          officialEvent.eventType != CategoriaActualizadaPayload.eventType) {
        continue;
      }
      final officialPayload = CategoriaActualizadaPayload.fromJson(
        officialEvent.payload,
      );
      officialChangedFields.addAll(officialPayload.changedFields);
    }

    final conflicts = payload.changedFields
        .where(officialChangedFields.contains)
        .toSet();
    if (conflicts.isEmpty) return null;

    return _PendingConflict(
      'La categoría cambió en los campos: ${conflicts.join(', ')}.',
      officialChangedFields: conflicts,
    );
  }

  Future<void> _hideConflictProjection(
    SyncEvent event,
    _PendingConflict conflict,
  ) async {
    switch (event.eventType) {
      case EspacioCreadoPayload.eventType:
        await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
      case CategoriaCreadaPayload.eventType:
        await _categoriaProjectionStore.deleteCreatedByEvent(event.eventId);
      case CategoriaActualizadaPayload.eventType:
        await _categoriaConflictProjectionRestorer.restore(
          event,
          officialChangedFields: conflict.officialChangedFields,
        );
    }
  }

  Future<_PendingConflict?> _espacioCreadoConflict(SyncEvent event) async {
    final existingById = await _espacioProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return _PendingConflict(
        'Ya existe un espacio oficial con id ${event.aggregateId}.',
      );
    }

    final payload = EspacioCreadoPayload.fromJson(event.payload);
    final identificacion = payload.identificacion;
    if (identificacion == null) return null;

    final existingByIdentificacion = await _espacioProjectionStore
        .findByIdentificacion(identificacion);

    if (existingByIdentificacion != null &&
        existingByIdentificacion.createdEventId != event.eventId) {
      return _PendingConflict(
        'Ya existe un espacio oficial con identificacion $identificacion.',
      );
    }

    return null;
  }
}

class _PendingConflict {
  const _PendingConflict(this.reason, {this.officialChangedFields = const {}});

  final String reason;
  final Set<String> officialChangedFields;
}
