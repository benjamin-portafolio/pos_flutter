import '../models/sync_event.dart';
import '../payloads/cliente_creado_payload.dart';
import '../projections/cliente_projection_store.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';

class ClientePendingEventValidator implements PendingEventValidator {
  ClientePendingEventValidator(this._store);
  final ClienteProjectionStore _store;
  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    ClienteCreadoPayload.fromJson(event.payload);
    final existing = await _store.findById(event.aggregateId);
    return existing != null && existing.createdEventId != event.eventId
        ? PendingConflict(
            'Ya existe un cliente oficial con id ${event.aggregateId}.',
          )
        : null;
  }

  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) =>
      _store.deleteCreatedByEvent(event.eventId);
}
