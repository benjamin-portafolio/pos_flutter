import '../models/sync_event.dart';
import '../payloads/proveedor_actualizado_payload.dart';
import '../proveedor_conflict_projection_restorer.dart';
import '../synced_event_history.dart';
import 'pending_event_dependency_resolver.dart';
import '../payloads/proveedor_creado_payload.dart';
import '../projections/proveedor_projection_store.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';

class ProveedorPendingEventValidator implements PendingEventValidator {
  ProveedorPendingEventValidator(this._store, this._history);
  final SyncedEventHistory _history;
  final ProveedorProjectionStore _store;
  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    if (event.eventType == ProveedorActualizadoPayload.eventType) {
      final payload = ProveedorActualizadoPayload.fromJson(event.payload);
      final dependencies = PendingEventDependencyResolver(_history);
      if (conflictedEventIds.contains(payload.baseEventId) ||
          await dependencies.hasFailed(payload.baseEventId)) {
        return const PendingConflict(
          'La edición depende de un evento en conflicto.',
        );
      }
      final current = await _store.findById(event.aggregateId);
      if (current == null || !current.active) {
        return const PendingConflict('El proveedor ya no está disponible.');
      }
      final base = await dependencies.resolveBase(
        baseEventId: payload.baseEventId,
        fallbackServerSequence: event.baseServerSequence,
      );
      if (!base.waitsForLocalDependency && base.serverSequence != null) {
        final official = await _history.eventsForAggregateAfter(
          aggregateType: ProveedorActualizadoPayload.aggregateType,
          aggregateId: event.aggregateId,
          serverSequence: base.serverSequence!,
        );
        if (official.any((e) => e.eventId != event.eventId)) {
          return const PendingConflict(
            'El proveedor cambió oficialmente desde la base local.',
          );
        }
      }
      return null;
    }
    ProveedorCreadoPayload.fromJson(event.payload);
    final existing = await _store.findById(event.aggregateId);
    return existing != null && existing.createdEventId != event.eventId
        ? PendingConflict(
            'Ya existe un proveedor oficial con id ${event.aggregateId}.',
          )
        : null;
  }

  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) =>
      event.eventType == ProveedorActualizadoPayload.eventType
      ? ProveedorConflictProjectionRestorer(_store).restore(event)
      : _store.deleteCreatedByEvent(event.eventId);
}
