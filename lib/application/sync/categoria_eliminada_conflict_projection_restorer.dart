import 'models/sync_event.dart';
import 'payloads/categoria_eliminada_payload.dart';
import 'projections/categoria_projection_store.dart';

class CategoriaEliminadaConflictProjectionRestorer {
  CategoriaEliminadaConflictProjectionRestorer(this._categoriaProjectionStore);

  final CategoriaProjectionStore _categoriaProjectionStore;

  Future<void> restore(SyncEvent event) async {
    final payload = CategoriaEliminadaPayload.fromJson(event.payload);

    for (final shifted in payload.categoriasDesplazadas.reversed) {
      final existing = await _categoriaProjectionStore.findById(
        shifted.categoriaId,
      );
      if (existing == null ||
          existing.lastEventId != event.eventId ||
          existing.orden != shifted.ordenNuevo) {
        continue;
      }
      await _categoriaProjectionStore.update(
        CategoriaProjection(
          id: existing.id,
          nombre: existing.nombre,
          color: existing.color,
          orden: shifted.ordenAnterior,
          active: existing.active,
          version: shifted.baseVersion,
          createdEventId: existing.createdEventId,
          lastEventId: shifted.baseEventId,
          lastServerSequence: shifted.baseServerSequence,
        ),
      );
    }

    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existing != null) return;

    final snapshot = payload.categoriaEliminada;
    await _categoriaProjectionStore.insert(
      CategoriaProjection(
        id: event.aggregateId,
        nombre: snapshot.nombre,
        color: snapshot.color,
        orden: snapshot.orden,
        active: snapshot.active,
        version: event.baseVersion ?? 1,
        createdEventId: snapshot.createdEventId,
        lastEventId: payload.baseEventId,
        lastServerSequence: event.baseServerSequence,
      ),
    );
  }
}
