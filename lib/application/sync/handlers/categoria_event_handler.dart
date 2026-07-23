import '../models/sync_event.dart';
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
