import 'categoria_conflict_projection_restorer.dart';
import 'categoria_eliminada_conflict_projection_restorer.dart';
import 'categoria_movida_conflict_projection_restorer.dart';
import 'models/pending_revalidation_report.dart';
import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/categoria_eliminada_payload.dart';
import 'payloads/categoria_movida_payload.dart';
import 'payloads/espacio_creado_payload.dart';
import 'payloads/producto_creado_payload.dart';
import 'payloads/recurso_inventario_creado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/espacio_projection_store.dart';
import 'projections/producto_projection_store.dart';
import 'projections/inventory_projection_store.dart';
import 'sync_persistence.dart';
import 'synced_event_history.dart';

class PendingEventRevalidator {
  PendingEventRevalidator({
    required SyncPersistence syncPersistence,
    required SyncedEventHistory syncedEventHistory,
    required EspacioProjectionStore espacioProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
    ProductoProjectionStore? productoProjectionStore,
    InventoryProjectionStore? inventoryProjectionStore,
    required CategoriaConflictProjectionRestorer
    categoriaConflictProjectionRestorer,
    required CategoriaMovidaConflictProjectionRestorer
    categoriaMovidaConflictProjectionRestorer,
    CategoriaEliminadaConflictProjectionRestorer?
    categoriaEliminadaConflictProjectionRestorer,
  }) : _syncPersistence = syncPersistence,
       _syncedEventHistory = syncedEventHistory,
       _espacioProjectionStore = espacioProjectionStore,
       _categoriaProjectionStore = categoriaProjectionStore,
       _productoProjectionStore = productoProjectionStore,
       _inventoryProjectionStore = inventoryProjectionStore,
       _categoriaConflictProjectionRestorer =
           categoriaConflictProjectionRestorer,
       _categoriaMovidaConflictProjectionRestorer =
           categoriaMovidaConflictProjectionRestorer,
       _categoriaEliminadaConflictProjectionRestorer =
           categoriaEliminadaConflictProjectionRestorer;

  final SyncPersistence _syncPersistence;
  final SyncedEventHistory _syncedEventHistory;
  final EspacioProjectionStore _espacioProjectionStore;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final ProductoProjectionStore? _productoProjectionStore;
  final InventoryProjectionStore? _inventoryProjectionStore;
  final CategoriaConflictProjectionRestorer
  _categoriaConflictProjectionRestorer;
  final CategoriaMovidaConflictProjectionRestorer
  _categoriaMovidaConflictProjectionRestorer;
  final CategoriaEliminadaConflictProjectionRestorer?
  _categoriaEliminadaConflictProjectionRestorer;

  Future<PendingRevalidationReport> revalidatePendingEvents() async {
    final events = await _syncPersistence.pendingEvents();
    final detected = <({SyncEvent event, _PendingConflict conflict})>[];
    final conflictedEventIds = <String>{};

    for (final event in events) {
      final dependencyConflict = await _dependencyConflict(
        event,
        conflictedEventIds,
      );
      final conflict =
          dependencyConflict ??
          switch (event.eventType) {
            EspacioCreadoPayload.eventType => await _espacioCreadoConflict(
              event,
            ),
            CategoriaCreadaPayload.eventType => await _categoriaCreadaConflict(
              event,
            ),
            CategoriaActualizadaPayload.eventType =>
              await _categoriaActualizadaConflict(event),
            CategoriaMovidaPayload.eventType => await _categoriaMovidaConflict(
              event,
            ),
            CategoriaEliminadaPayload.eventType =>
              await _categoriaEliminadaConflict(event),
            ProductoCreadoPayload.eventType => await _productoCreadoConflict(
              event,
            ),
            RecursoInventarioCreadoPayload.eventType =>
              await _inventoryItemCreadoConflict(event),
            _ => null,
          };

      if (conflict == null) continue;

      detected.add((event: event, conflict: conflict));
      conflictedEventIds.add(event.eventId);
    }

    await _syncPersistence.runInTransaction(() async {
      for (final entry in detected) {
        await _syncPersistence.updateEventSyncStatus(
          entry.event.eventId,
          'conflict',
          rejectionReason: entry.conflict.reason,
        );
      }
      for (final entry in detected.reversed) {
        await _hideConflictProjection(entry.event, entry.conflict);
      }
    });

    return PendingRevalidationReport(
      checked: events.length,
      conflicts: detected.length,
    );
  }

  Future<_PendingConflict?> _dependencyConflict(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    if (event.eventType == CategoriaActualizadaPayload.eventType) {
      final payload = CategoriaActualizadaPayload.fromJson(event.payload);
      if (conflictedEventIds.contains(payload.baseEventId) ||
          await _dependencyFailed(payload.baseEventId)) {
        return const _PendingConflict(
          'La categoría depende de otro evento local en conflicto.',
        );
      }
    }
    if (event.eventType == CategoriaMovidaPayload.eventType) {
      final payload = CategoriaMovidaPayload.fromJson(event.payload);
      if (conflictedEventIds.contains(payload.baseEventId) ||
          conflictedEventIds.contains(payload.categoriaDesplazadaBaseEventId) ||
          await _dependencyFailed(payload.baseEventId) ||
          await _dependencyFailed(payload.categoriaDesplazadaBaseEventId)) {
        return const _PendingConflict(
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
            await _dependencyFailed(baseEventId)) {
          return const _PendingConflict(
            'La eliminación depende de otro evento local en conflicto.',
          );
        }
      }
    }
    if (event.eventType == ProductoCreadoPayload.eventType) {
      final payload = ProductoCreadoPayload.fromJson(event.payload);
      final dependencyEventId = payload.dependenciaCategoria?.dependsOnEventId;
      if (dependencyEventId != null &&
          (conflictedEventIds.contains(dependencyEventId) ||
              await _dependencyFailed(dependencyEventId))) {
        return const _PendingConflict(
          'El artículo depende de una categoría local en conflicto.',
        );
      }
    }
    return null;
  }

  Future<_PendingConflict?> _productoCreadoConflict(SyncEvent event) async {
    final store = _productoProjectionStore;
    if (store == null) return null;

    final existing = await store.findProductById(event.aggregateId);
    if (existing != null && existing.createdEventId != event.eventId) {
      return _PendingConflict(
        'Ya existe un artículo oficial con id ${event.aggregateId}.',
      );
    }
    final payload = ProductoCreadoPayload.fromJson(event.payload);
    for (final payloadVariant in payload.variantes) {
      final variant = await store.findVariantById(payloadVariant.id);
      if (variant != null && variant.createdEventId != event.eventId) {
        return _PendingConflict(
          'Ya existe una variante oficial con id ${payloadVariant.id}.',
        );
      }
    }
    if (payload.categoriaId != null &&
        await _categoriaProjectionStore.findById(payload.categoriaId!) ==
            null) {
      return const _PendingConflict(
        'Ya no existe la categoría elegida para el artículo.',
      );
    }
    return null;
  }

  Future<_PendingConflict?> _inventoryItemCreadoConflict(
    SyncEvent event,
  ) async {
    final store = _inventoryProjectionStore;
    if (store == null) return null;
    final payload = RecursoInventarioCreadoPayload.fromJson(event.payload);
    final item = await store.findItemById(event.aggregateId);
    if (item != null && item.createdEventId != event.eventId) {
      return _PendingConflict(
        'Ya existe un recurso oficial con id ${event.aggregateId}.',
      );
    }
    final movementId = payload.initialMovement?.movementId;
    if (movementId != null) {
      final movement = await store.findMovementById(movementId);
      if (movement != null && movement.eventId != event.eventId) {
        return _PendingConflict(
          'Ya existe un movimiento oficial con id $movementId.',
        );
      }
    }
    final unit = await store.findUnitById(payload.defaultUnitId);
    if (unit == null || !unit.active) {
      return const _PendingConflict(
        'La unidad del recurso ya no existe o está inactiva.',
      );
    }
    return null;
  }

  Future<bool> _dependencyFailed(String eventId) async {
    final dependency = await _syncedEventHistory.eventById(eventId);
    return dependency?.deliveryStatus == 'conflict' ||
        dependency?.deliveryStatus == 'rejected';
  }

  Future<_PendingConflict?> _categoriaCreadaConflict(SyncEvent event) async {
    final existingById = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return _PendingConflict(
        'Ya existe una categoría oficial con id ${event.aggregateId}.',
      );
    }
    return null;
  }

  Future<_PendingConflict?> _categoriaActualizadaConflict(
    SyncEvent event,
  ) async {
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existing == null) {
      return _PendingConflict(
        'Ya no existe la categoría que se intentó actualizar.',
      );
    }

    final payload = CategoriaActualizadaPayload.fromJson(event.payload);
    final resolvedBase = await _resolveBase(
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

    return _PendingConflict(
      'La categoría cambió en los campos: ${conflicts.join(', ')}.',
      officialChangedFields: conflicts,
    );
  }

  Future<_PendingConflict?> _categoriaMovidaConflict(SyncEvent event) async {
    final payload = CategoriaMovidaPayload.fromJson(event.payload);
    final moved = await _categoriaProjectionStore.findById(event.aggregateId);
    final displaced = await _categoriaProjectionStore.findById(
      payload.categoriaDesplazadaId,
    );
    if (moved == null || displaced == null) {
      return const _PendingConflict(
        'Ya no existe una categoría involucrada en el movimiento.',
      );
    }

    final movedBase = await _resolveBase(
      baseEventId: payload.baseEventId,
      fallbackServerSequence: event.baseServerSequence,
    );
    final displacedBase = await _resolveBase(
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
    return _PendingConflict(
      'El orden cambió oficialmente para una categoría involucrada.',
      officialCategoryIds: officialCategoryIds,
    );
  }

  Future<_PendingConflict?> _categoriaEliminadaConflict(SyncEvent event) async {
    final payload = CategoriaEliminadaPayload.fromJson(event.payload);
    payload.validateForSourceCategory(event.aggregateId);
    final store = _productoProjectionStore;
    if (store != null &&
        (await store.findProductsByCategoryId(event.aggregateId)).isNotEmpty) {
      return const _PendingConflict(
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
          return const _PendingConflict(
            'Cambió un artículo confirmado antes de eliminar la categoría.',
          );
        }
      }
    }
    final restored = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (restored != null) {
      return const _PendingConflict(
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
        return const _PendingConflict(
          'La categoría destino cambió antes de eliminar la categoría origen.',
        );
      }
    }
    for (final shifted in payload.categoriasDesplazadas) {
      final existing = await _categoriaProjectionStore.findById(
        shifted.categoriaId,
      );
      if (existing == null) {
        return const _PendingConflict(
          'Ya no existe una categoría afectada por la compactación.',
        );
      }
      final hasNewerOfficialState =
          existing.lastServerSequence != null &&
          (shifted.baseServerSequence == null ||
              existing.lastServerSequence! > shifted.baseServerSequence!);
      if (hasNewerOfficialState && existing.lastEventId != event.eventId) {
        return const _PendingConflict(
          'El orden cambió oficialmente antes de eliminar la categoría.',
        );
      }
    }
    return null;
  }

  Future<_ResolvedBase> _resolveBase({
    required String baseEventId,
    required int? fallbackServerSequence,
  }) async {
    final baseEvent = await _syncedEventHistory.eventById(baseEventId);
    if (baseEvent == null) {
      return _ResolvedBase(serverSequence: fallbackServerSequence);
    }

    if (baseEvent.deliveryStatus != 'delivered' ||
        baseEvent.serverSequence == null) {
      return const _ResolvedBase(waitsForLocalDependency: true);
    }

    final officialSequence = baseEvent.serverSequence!;
    final effectiveSequence =
        fallbackServerSequence == null ||
            officialSequence > fallbackServerSequence
        ? officialSequence
        : fallbackServerSequence;
    return _ResolvedBase(serverSequence: effectiveSequence);
  }

  Future<void> _hideConflictProjection(
    SyncEvent event,
    _PendingConflict conflict,
  ) async {
    switch (event.eventType) {
      case EspacioCreadoPayload.eventType:
        await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
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
      case ProductoCreadoPayload.eventType:
        await _productoProjectionStore?.deleteCreatedByEvent(event.eventId);
      case RecursoInventarioCreadoPayload.eventType:
        await _inventoryProjectionStore?.deleteCreatedByEvent(event.eventId);
    }
  }

  Future<_PendingConflict?> _espacioCreadoConflict(SyncEvent event) async {
    final existingById = await _espacioProjectionStore.findById(
      event.aggregateId,
    );
    if (existingById != null && existingById.createdEventId != event.eventId) {
      return _PendingConflict(
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
      return _PendingConflict(
        'Ya existe un espacio oficial con identificacion $identificacion.',
      );
    }

    return null;
  }
}

class _PendingConflict {
  const _PendingConflict(
    this.reason, {
    this.officialChangedFields = const {},
    this.officialCategoryIds = const {},
  });

  final String reason;
  final Set<String> officialChangedFields;
  final Set<String> officialCategoryIds;
}

class _ResolvedBase {
  const _ResolvedBase({
    this.serverSequence,
    this.waitsForLocalDependency = false,
  });

  final int? serverSequence;
  final bool waitsForLocalDependency;
}
