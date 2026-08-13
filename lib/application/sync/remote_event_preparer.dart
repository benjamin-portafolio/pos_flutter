import 'categoria_eliminada_conflict_projection_restorer.dart';
import 'models/sync_event.dart';
import 'payloads/categoria_eliminada_payload.dart';
import 'payloads/categoria_movida_payload.dart';
import 'payloads/producto_creado_payload.dart';
import 'sync_conflict_projection_cleaner.dart';
import 'sync_persistence.dart';

class RemoteEventPreparer {
  RemoteEventPreparer({
    required SyncPersistence syncPersistence,
    required CategoriaEliminadaConflictProjectionRestorer
    categoriaEliminadaConflictProjectionRestorer,
    required SyncConflictProjectionCleaner conflictProjectionCleaner,
  }) : _syncPersistence = syncPersistence,
       _categoriaEliminadaConflictProjectionRestorer =
           categoriaEliminadaConflictProjectionRestorer,
       _conflictProjectionCleaner = conflictProjectionCleaner;

  final SyncPersistence _syncPersistence;
  final CategoriaEliminadaConflictProjectionRestorer
  _categoriaEliminadaConflictProjectionRestorer;
  final SyncConflictProjectionCleaner _conflictProjectionCleaner;

  Future<void> prepare(SyncEvent officialEvent) async {
    final pending = await _syncPersistence.pendingEvents();
    final refs = await _syncPersistence.refsForEvents(
      pending.map((event) => event.eventId).toList(growable: false),
    );

    final preparedConflictIds = <String>{};
    for (final local in pending) {
      if (local.eventType != CategoriaEliminadaPayload.eventType) continue;
      final affected =
          officialEvent.eventType == ProductoCreadoPayload.eventType
          ? ProductoCreadoPayload.fromJson(officialEvent.payload).categoriaId ==
                local.aggregateId
          : refs.any(
              (ref) =>
                  ref.eventId == local.eventId &&
                  ref.refType == 'category' &&
                  _officialCategoryIds(officialEvent).contains(ref.refId),
            );
      if (!affected) continue;

      await _categoriaEliminadaConflictProjectionRestorer.restore(local);
      await _syncPersistence.updateEventSyncStatus(
        local.eventId,
        'conflict',
        rejectionReason:
            'La categoría o el orden cambió oficialmente antes de eliminarse.',
      );
      preparedConflictIds.add(local.eventId);
    }

    if (officialEvent.eventType != CategoriaEliminadaPayload.eventType) {
      return;
    }
    final officialPayload = CategoriaEliminadaPayload.fromJson(
      officialEvent.payload,
    );
    final categoryIds = {
      officialEvent.aggregateId,
      ...officialPayload.categoriasDesplazadas.map(
        (category) => category.categoriaId,
      ),
    };
    for (final local in pending) {
      if (preparedConflictIds.contains(local.eventId)) continue;
      if (local.eventType == ProductoCreadoPayload.eventType) {
        final payload = ProductoCreadoPayload.fromJson(local.payload);
        if (payload.categoriaId != officialEvent.aggregateId) continue;
      } else {
        final affectsOrder = refs.any(
          (ref) =>
              ref.eventId == local.eventId &&
              ref.refType == 'category' &&
              categoryIds.contains(ref.refId),
        );
        if (!affectsOrder) continue;
      }

      await _conflictProjectionCleaner.hideConflictProjection(local);
      await _syncPersistence.updateEventSyncStatus(
        local.eventId,
        'conflict',
        rejectionReason:
            'La categoría del artículo fue eliminada oficialmente.',
      );
    }
  }

  Set<String> _officialCategoryIds(SyncEvent event) {
    switch (event.eventType) {
      case CategoriaEliminadaPayload.eventType:
        final payload = CategoriaEliminadaPayload.fromJson(event.payload);
        return {
          event.aggregateId,
          ...payload.categoriasDesplazadas.map(
            (category) => category.categoriaId,
          ),
        };
      case CategoriaMovidaPayload.eventType:
        final payload = CategoriaMovidaPayload.fromJson(event.payload);
        return {event.aggregateId, payload.categoriaDesplazadaId};
      case ProductoCreadoPayload.eventType:
        final payload = ProductoCreadoPayload.fromJson(event.payload);
        final categoryId = payload.categoriaId;
        return categoryId == null ? const <String>{} : {categoryId};
      default:
        return event.aggregateType == 'category'
            ? {event.aggregateId}
            : const <String>{};
    }
  }
}
