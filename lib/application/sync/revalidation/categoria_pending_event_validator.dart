import '../categoria_conflict_projection_restorer.dart';
import '../categoria_eliminada_conflict_projection_restorer.dart';
import '../categoria_movida_conflict_projection_restorer.dart';
import '../models/sync_event.dart';
import '../payloads/categoria_actualizada_payload.dart';
import '../payloads/categoria_creada_payload.dart';
import '../payloads/categoria_eliminada_payload.dart';
import '../payloads/categoria_movida_payload.dart';
import '../projections/categoria_projection_store.dart';
import '../projections/producto_projection_store.dart';
import '../synced_event_history.dart';
import 'pending_conflict.dart';
import 'pending_event_dependency_resolver.dart';
import 'pending_event_validator.dart';

class CategoriaPendingEventValidator implements PendingEventValidator {
  CategoriaPendingEventValidator({
    required CategoriaProjectionStore categoriaProjectionStore,
    required ProductoProjectionStore? productoProjectionStore,
    required SyncedEventHistory syncedEventHistory,
    required PendingEventDependencyResolver dependencies,
    required CategoriaConflictProjectionRestorer
    categoriaConflictProjectionRestorer,
    required CategoriaMovidaConflictProjectionRestorer
    categoriaMovidaConflictProjectionRestorer,
    required CategoriaEliminadaConflictProjectionRestorer?
    categoriaEliminadaConflictProjectionRestorer,
  }) : _categoriaProjectionStore = categoriaProjectionStore,
       _productoProjectionStore = productoProjectionStore,
       _syncedEventHistory = syncedEventHistory,
       _dependencies = dependencies,
       _categoriaConflictProjectionRestorer =
           categoriaConflictProjectionRestorer,
       _categoriaMovidaConflictProjectionRestorer =
           categoriaMovidaConflictProjectionRestorer,
       _categoriaEliminadaConflictProjectionRestorer =
           categoriaEliminadaConflictProjectionRestorer;

  final CategoriaProjectionStore _categoriaProjectionStore;
  final ProductoProjectionStore? _productoProjectionStore;
  final SyncedEventHistory _syncedEventHistory;
  final PendingEventDependencyResolver _dependencies;
  final CategoriaConflictProjectionRestorer
  _categoriaConflictProjectionRestorer;
  final CategoriaMovidaConflictProjectionRestorer
  _categoriaMovidaConflictProjectionRestorer;
  final CategoriaEliminadaConflictProjectionRestorer?
  _categoriaEliminadaConflictProjectionRestorer;

  @override
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    final dependencyConflict = await _dependencyConflict(
      event,
      conflictedEventIds,
    );
    if (dependencyConflict != null) return dependencyConflict;
    return switch (event.eventType) {
      CategoriaCreadaPayload.eventType => await _categoriaCreadaConflict(event),
      CategoriaActualizadaPayload.eventType =>
        await _categoriaActualizadaConflict(event),
      CategoriaMovidaPayload.eventType => await _categoriaMovidaConflict(event),
      CategoriaEliminadaPayload.eventType => await _categoriaEliminadaConflict(
        event,
      ),
      _ => null,
    };
  }

  Future<PendingConflict?> _dependencyConflict(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    if (event.eventType == CategoriaActualizadaPayload.eventType) {
      final payload = CategoriaActualizadaPayload.fromJson(event.payload);
      if (conflictedEventIds.contains(payload.baseEventId) ||
          await _dependencies.hasFailed(payload.baseEventId)) {
        return const PendingConflict(
          'La categoría depende de otro evento local en conflicto.',
        );
      }
    }
    if (event.eventType == CategoriaMovidaPayload.eventType) {
      final payload = CategoriaMovidaPayload.fromJson(event.payload);
      if (conflictedEventIds.contains(payload.baseEventId) ||
          conflictedEventIds.contains(payload.categoriaDesplazadaBaseEventId) ||
          await _dependencies.hasFailed(payload.baseEventId) ||
          await _dependencies.hasFailed(
            payload.categoriaDesplazadaBaseEventId,
          )) {
        return const PendingConflict(
          'El movimiento depende de otro evento local en conflicto.',
        );
      }
    }
    if (event.eventType == CategoriaEliminadaPayload.eventType) {
      final payload = CategoriaEliminadaPayload.fromJson(event.payload);
      final baseEventIds = {
        payload.baseEventId,
        if (payload.resolucionProductos.categoriaDestino != null)
          payload.resolucionProductos.categoriaDestino!.baseEventId,
        ...payload.productosVinculados.map((product) => product.baseEventId),
        ...payload.categoriasDesplazadas.map(
          (category) => category.baseEventId,
        ),
      };
      for (final baseEventId in baseEventIds) {
        if (conflictedEventIds.contains(baseEventId) ||
            await _dependencies.hasFailed(baseEventId)) {
          return const PendingConflict(
            'La eliminación depende de otro evento local en conflicto.',
          );
        }
      }
    }
    return null;
  }

  Future<PendingConflict?> _categoriaCreadaConflict(SyncEvent event) async {
    final existingById = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return PendingConflict(
        'Ya existe una categoría oficial con id ${event.aggregateId}.',
      );
    }
    return null;
  }

  Future<PendingConflict?> _categoriaActualizadaConflict(
    SyncEvent event,
  ) async {
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existing == null) {
      return PendingConflict(
        'Ya no existe la categoría que se intentó actualizar.',
      );
    }

    final payload = CategoriaActualizadaPayload.fromJson(event.payload);
    final resolvedBase = await _dependencies.resolveBase(
      baseEventId: payload.baseEventId,
      fallbackServerSequence: event.baseServerSequence,
    );
    if (resolvedBase.waitsForLocalDependency) return null;

    final baseServerSequence = resolvedBase.serverSequence;
    if (baseServerSequence == null) return null;

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

    return PendingConflict(
      'La categoría cambió en los campos: ${conflicts.join(', ')}.',
      officialChangedFields: conflicts,
    );
  }

  Future<PendingConflict?> _categoriaMovidaConflict(SyncEvent event) async {
    final payload = CategoriaMovidaPayload.fromJson(event.payload);
    final moved = await _categoriaProjectionStore.findById(event.aggregateId);
    final displaced = await _categoriaProjectionStore.findById(
      payload.categoriaDesplazadaId,
    );
    if (moved == null || displaced == null) {
      return const PendingConflict(
        'Ya no existe una categoría involucrada en el movimiento.',
      );
    }

    final movedBase = await _dependencies.resolveBase(
      baseEventId: payload.baseEventId,
      fallbackServerSequence: event.baseServerSequence,
    );
    final displacedBase = await _dependencies.resolveBase(
      baseEventId: payload.categoriaDesplazadaBaseEventId,
      fallbackServerSequence: payload.categoriaDesplazadaBaseServerSequence,
    );
    if (movedBase.waitsForLocalDependency &&
        displacedBase.waitsForLocalDependency) {
      return null;
    }

    final movedSequence = movedBase.serverSequence ?? -1;
    final displacedSequence = displacedBase.serverSequence ?? -1;
    final historyStart = switch ((
      movedBase.waitsForLocalDependency,
      displacedBase.waitsForLocalDependency,
    )) {
      (true, false) => displacedSequence,
      (false, true) => movedSequence,
      (false, false) =>
        movedSequence < displacedSequence ? movedSequence : displacedSequence,
      (true, true) => -1,
    };
    final officialEvents = await _syncedEventHistory.eventsByTypeAfter(
      eventType: CategoriaMovidaPayload.eventType,
      serverSequence: historyStart,
    );
    final officialCategoryIds = <String>{};
    final localCategoryIds = {event.aggregateId, payload.categoriaDesplazadaId};

    for (final officialEvent in officialEvents) {
      if (officialEvent.eventId == event.eventId) continue;
      final officialPayload = CategoriaMovidaPayload.fromJson(
        officialEvent.payload,
      );
      final officialIds = {
        officialEvent.aggregateId,
        officialPayload.categoriaDesplazadaId,
      };
      final sequence = officialEvent.serverSequence;
      if (sequence == null) continue;

      if (!movedBase.waitsForLocalDependency &&
          sequence > movedSequence &&
          officialIds.contains(event.aggregateId)) {
        officialCategoryIds.add(event.aggregateId);
      }
      if (!displacedBase.waitsForLocalDependency &&
          sequence > displacedSequence &&
          officialIds.contains(payload.categoriaDesplazadaId)) {
        officialCategoryIds.add(payload.categoriaDesplazadaId);
      }
    }

    officialCategoryIds.retainAll(localCategoryIds);
    if (officialCategoryIds.isEmpty) return null;
    return PendingConflict(
      'El orden cambió oficialmente para una categoría involucrada.',
      officialCategoryIds: officialCategoryIds,
    );
  }

  Future<PendingConflict?> _categoriaEliminadaConflict(SyncEvent event) async {
    final payload = CategoriaEliminadaPayload.fromJson(event.payload);
    payload.validateForSourceCategory(event.aggregateId);
    final store = _productoProjectionStore;
    if (store != null &&
        (await store.findProductsByCategoryId(event.aggregateId)).isNotEmpty) {
      return const PendingConflict(
        'La categoría recibió artículos oficiales antes de eliminarse.',
      );
    }
    if (store != null) {
      for (final linked in payload.productosVinculados) {
        final current = await store.findProductById(linked.productoId);
        if (current == null ||
            current.categoriaId != linked.categoriaNuevaId ||
            current.lastEventId != event.eventId ||
            current.version != linked.baseVersion + 1) {
          return const PendingConflict(
            'Cambió un artículo confirmado antes de eliminar la categoría.',
          );
        }
      }
    }
    final restored = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (restored != null) {
      return const PendingConflict(
        'La categoría cambió oficialmente antes de eliminarse.',
      );
    }
    final destination = payload.resolucionProductos.categoriaDestino;
    if (destination != null) {
      final current = await _categoriaProjectionStore.findById(
        destination.categoriaId,
      );
      CategoriaEliminadaCategoriaDesplazada? shifted;
      for (final category in payload.categoriasDesplazadas) {
        if (category.categoriaId == destination.categoriaId) {
          shifted = category;
          break;
        }
      }
      final baseEventId = current?.lastEventId ?? current?.createdEventId;
      final matches = shifted == null
          ? current != null &&
                current.active &&
                baseEventId == destination.baseEventId &&
                current.version == destination.baseVersion &&
                (destination.baseServerSequence == null ||
                    current.lastServerSequence ==
                        destination.baseServerSequence)
          : current != null &&
                current.active &&
                current.lastEventId == event.eventId &&
                current.version == destination.baseVersion + 1 &&
                current.orden == shifted.ordenNuevo;
      if (!matches) {
        return const PendingConflict(
          'La categoría destino cambió antes de eliminar la categoría origen.',
        );
      }
    }
    for (final shifted in payload.categoriasDesplazadas) {
      final existing = await _categoriaProjectionStore.findById(
        shifted.categoriaId,
      );
      if (existing == null) {
        return const PendingConflict(
          'Ya no existe una categoría afectada por la compactación.',
        );
      }
      final hasNewerOfficialState =
          existing.lastServerSequence != null &&
          (shifted.baseServerSequence == null ||
              existing.lastServerSequence! > shifted.baseServerSequence!);
      if (hasNewerOfficialState && existing.lastEventId != event.eventId) {
        return const PendingConflict(
          'El orden cambió oficialmente antes de eliminar la categoría.',
        );
      }
    }
    return null;
  }

  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {
    switch (event.eventType) {
      case CategoriaCreadaPayload.eventType:
        await _categoriaProjectionStore.deleteCreatedByEvent(event.eventId);
      case CategoriaActualizadaPayload.eventType:
        await _categoriaConflictProjectionRestorer.restore(
          event,
          officialChangedFields: conflict.officialChangedFields,
        );
      case CategoriaMovidaPayload.eventType:
        await _categoriaMovidaConflictProjectionRestorer.restore(
          event,
          officialCategoryIds: conflict.officialCategoryIds,
        );
      case CategoriaEliminadaPayload.eventType:
        await _categoriaEliminadaConflictProjectionRestorer?.restore(event);
    }
  }
}
