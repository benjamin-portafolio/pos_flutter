import 'models/sync_event.dart';
import 'payloads/categoria_movida_payload.dart';
import 'projections/categoria_projection_store.dart';

class CategoriaMovidaConflictProjectionRestorer {
  CategoriaMovidaConflictProjectionRestorer(this._categoriaProjectionStore);

  final CategoriaProjectionStore _categoriaProjectionStore;

  Future<void> restore(
    SyncEvent event, {
    Set<String> officialCategoryIds = const {},
  }) async {
    final payload = CategoriaMovidaPayload.fromJson(event.payload);
    final moved = await _categoriaProjectionStore.findById(event.aggregateId);
    final displaced = await _categoriaProjectionStore.findById(
      payload.categoriaDesplazadaId,
    );

    if (moved != null) {
      await _restoreProjection(
        moved,
        event: event,
        baseEventId: payload.baseEventId,
        baseVersion: event.baseVersion,
        baseServerSequence: event.baseServerSequence,
        localOrder: payload.ordenNuevo,
        restoredOrder: payload.ordenAnterior,
        preserveOfficial: officialCategoryIds.contains(moved.id),
      );
    }
    if (displaced != null) {
      await _restoreProjection(
        displaced,
        event: event,
        baseEventId: payload.categoriaDesplazadaBaseEventId,
        baseVersion: payload.categoriaDesplazadaBaseVersion,
        baseServerSequence: payload.categoriaDesplazadaBaseServerSequence,
        localOrder: payload.categoriaDesplazadaOrdenNuevo,
        restoredOrder: payload.categoriaDesplazadaOrdenAnterior,
        preserveOfficial: officialCategoryIds.contains(displaced.id),
      );
    }
  }

  Future<void> _restoreProjection(
    CategoriaProjection existing, {
    required SyncEvent event,
    required String baseEventId,
    required int? baseVersion,
    required int? baseServerSequence,
    required int localOrder,
    required int restoredOrder,
    required bool preserveOfficial,
  }) {
    final eventIsLatest = existing.lastEventId == event.eventId;
    final shouldRestoreOrder =
        !preserveOfficial && existing.orden == localOrder;
    final shouldRestoreMetadata = eventIsLatest && !preserveOfficial;

    return _categoriaProjectionStore.update(
      CategoriaProjection(
        id: existing.id,
        nombre: existing.nombre,
        color: existing.color,
        orden: shouldRestoreOrder ? restoredOrder : existing.orden,
        active: existing.active,
        version: shouldRestoreMetadata
            ? baseVersion ?? existing.version
            : existing.version,
        createdEventId: existing.createdEventId,
        lastEventId: shouldRestoreMetadata ? baseEventId : existing.lastEventId,
        lastServerSequence: shouldRestoreMetadata
            ? baseServerSequence
            : existing.lastServerSequence,
      ),
    );
  }
}
