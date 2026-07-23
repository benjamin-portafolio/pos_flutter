import '../models/sync_event.dart';
import '../payloads/categoria_actualizada_payload.dart';
import '../payloads/categoria_creada_payload.dart';
import '../projections/categoria_projection_store.dart';

class CategoriaEventHandler {
  CategoriaEventHandler(this._categoriaProjectionStore);

  final CategoriaProjectionStore _categoriaProjectionStore;

  Future<void> applyCategoriaCreada(SyncEvent event) async {
    final payload = CategoriaCreadaPayload.fromJson(event.payload);
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );

    if (existing != null) {
      if (existing.createdEventId == event.eventId) {
        await _categoriaProjectionStore.updateSyncMetadata(
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
          'No se puede aplicar categoria_creada sobre una categoría existente: '
          '${event.aggregateId}',
        );
      }
    }

    await _categoriaProjectionStore.insert(
      CategoriaProjection(
        id: event.aggregateId,
        nombre: payload.nombre,
        color: payload.color,
        orden: payload.orden,
        active: true,
        version: event.baseVersion ?? 1,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence,
      ),
    );
  }

  Future<void> applyCategoriaActualizada(SyncEvent event) async {
    final payload = CategoriaActualizadaPayload.fromJson(event.payload);
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existing == null) {
      throw StateError(
        'No se puede aplicar categoria_actualizada porque no existe: '
        '${event.aggregateId}',
      );
    }

    if (existing.lastEventId == event.eventId) {
      await _categoriaProjectionStore.updateSyncMetadata(
        existing.id,
        eventId: event.eventId,
        serverSequence: event.serverSequence,
      );
      return;
    }

    final serverSequence = event.serverSequence;
    final currentServerSequence = existing.lastServerSequence;
    if (serverSequence != null &&
        currentServerSequence != null &&
        serverSequence <= currentServerSequence) {
      return;
    }

    if (serverSequence == null) {
      _validateLocalBase(event, payload, existing);
    }

    final remoteVersion = event.baseVersion == null
        ? existing.version + 1
        : event.baseVersion! + 1;
    await _categoriaProjectionStore.update(
      CategoriaProjection(
        id: existing.id,
        nombre: payload.nombreNuevo ?? existing.nombre,
        color: payload.colorNuevo ?? existing.color,
        orden: existing.orden,
        active: existing.active,
        version: serverSequence == null
            ? existing.version + 1
            : _max(existing.version, remoteVersion),
        createdEventId: existing.createdEventId,
        lastEventId: event.eventId,
        lastServerSequence: serverSequence ?? existing.lastServerSequence,
      ),
    );
  }

  void _validateLocalBase(
    SyncEvent event,
    CategoriaActualizadaPayload payload,
    CategoriaProjection existing,
  ) {
    if (event.baseVersion != existing.version) {
      throw StateError(
        'categoria_actualizada partió de una versión local obsoleta.',
      );
    }
    if (payload.cambiaNombre && payload.nombreAnterior != existing.nombre) {
      throw StateError(
        'categoria_actualizada no coincide con el nombre local actual.',
      );
    }
    if (payload.cambiaColor && payload.colorAnterior != existing.color) {
      throw StateError(
        'categoria_actualizada no coincide con el color local actual.',
      );
    }
  }

  int _max(int left, int right) => left > right ? left : right;

  Future<bool> _removeLocalPendingProjectionForRemoteEvent(
    SyncEvent event,
    CategoriaProjection existing,
  ) async {
    if (event.serverSequence == null || existing.lastServerSequence != null) {
      return false;
    }

    await _categoriaProjectionStore.deleteById(existing.id);
    return true;
  }
}
