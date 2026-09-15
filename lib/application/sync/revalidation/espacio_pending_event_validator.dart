import '../models/sync_event.dart';
import '../payloads/espacio_creado_payload.dart';
import '../projections/espacio_projection_store.dart';
import 'pending_conflict.dart';
import 'pending_event_validator.dart';

class EspacioPendingEventValidator implements PendingEventValidator {
  EspacioPendingEventValidator({
    required EspacioProjectionStore espacioProjectionStore,
  }) : _espacioProjectionStore = espacioProjectionStore;

  final EspacioProjectionStore _espacioProjectionStore;

  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    return switch (event.eventType) {
      EspacioCreadoPayload.eventType => await _espacioCreadoConflict(event),
      _ => null,
    };
  }

  Future<PendingConflict?> _espacioCreadoConflict(SyncEvent event) async {
    final existingById = await _espacioProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return PendingConflict(
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
      return PendingConflict(
        'Ya existe un espacio oficial con identificacion $identificacion.',
      );
    }

    return null;
  }

  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {
    switch (event.eventType) {
      case EspacioCreadoPayload.eventType:
        await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
    }
  }
}
