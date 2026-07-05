import '../../../domain/espacios/visibilidad_espacio.dart';
import '../models/sync_event.dart';
import '../projections/espacio_projection_store.dart';

class EspacioEventHandler {
  EspacioEventHandler(this._espacioProjectionStore);

  final EspacioProjectionStore _espacioProjectionStore;

  Future<void> applyEspacioCreado(SyncEvent event) async {
    final payload = event.payload;
    final identificacion = payload['identificacion'] as String?;
    final existing = await _espacioProjectionStore.findById(event.aggregateId);

    if (existing != null) {
      if (existing.createdEventId == event.eventId) {
        await _espacioProjectionStore.updateSyncMetadata(
          event.aggregateId,
          eventId: event.eventId,
          serverSequence: event.serverSequence,
        );
        return;
      }

      final removedLocalPending =
          await _removeLocalPendingProjectionForRemoteEvent(event, existing);
      if (!removedLocalPending) {
        throw StateError(
          'No se puede aplicar espacio_creado sobre un espacio existente: '
          '${event.aggregateId}',
        );
      }
    }

    if (identificacion != null && identificacion.isNotEmpty) {
      final existingByIdentificacion = await _espacioProjectionStore
          .findByIdentificacion(identificacion);

      if (existingByIdentificacion != null) {
        final removedLocalPending =
            await _removeLocalPendingProjectionForRemoteEvent(
              event,
              existingByIdentificacion,
            );
        if (!removedLocalPending) {
          throw StateError(
            'No se puede aplicar espacio_creado con identificacion duplicada: '
            '$identificacion',
          );
        }
      }
    }

    await _espacioProjectionStore.insert(
      EspacioProjection(
        id: event.aggregateId,
        nombre: payload['nombre']! as String,
        identificacion: identificacion,
        visibilidad: visibilidadEspacioFromEventValue(payload['visibilidad']),
        active: true,
        version: event.baseVersion ?? 1,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence,
      ),
    );
  }

  Future<bool> _removeLocalPendingProjectionForRemoteEvent(
    SyncEvent event,
    EspacioProjection existing,
  ) async {
    if (event.serverSequence == null || existing.lastServerSequence != null) {
      return false;
    }

    await _espacioProjectionStore.deleteById(existing.id);
    return true;
  }
}
