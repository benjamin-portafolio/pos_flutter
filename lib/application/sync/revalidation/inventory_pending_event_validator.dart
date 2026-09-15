import '../models/sync_event.dart';
import '../payloads/movimiento_inventario_registrado_payload.dart';
import '../payloads/recurso_inventario_actualizado_payload.dart';
import '../payloads/recurso_inventario_creado_payload.dart';
import '../projections/inventory_projection_store.dart';
import '../synced_event_history.dart';
import 'pending_conflict.dart';
import 'pending_event_dependency_resolver.dart';
import 'pending_event_validator.dart';

class InventoryPendingEventValidator implements PendingEventValidator {
  InventoryPendingEventValidator({
    required InventoryProjectionStore? inventoryProjectionStore,
    required SyncedEventHistory syncedEventHistory,
    required PendingEventDependencyResolver dependencies,
  }) : _inventoryProjectionStore = inventoryProjectionStore,
       _syncedEventHistory = syncedEventHistory,
       _dependencies = dependencies;

  final InventoryProjectionStore? _inventoryProjectionStore;
  final SyncedEventHistory _syncedEventHistory;
  final PendingEventDependencyResolver _dependencies;

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
      RecursoInventarioCreadoPayload.eventType =>
        await _inventoryItemCreadoConflict(event),
      RecursoInventarioActualizadoPayload.eventType =>
        await _inventoryMutationConflict(event),
      MovimientoInventarioRegistradoPayload.eventType =>
        await _inventoryMutationConflict(event),
      _ => null,
    };
  }

  Future<PendingConflict?> _dependencyConflict(
    SyncEvent event,
    Set<String> conflictedEventIds,
  ) async {
    if (event.eventType == RecursoInventarioActualizadoPayload.eventType) {
      final payload = RecursoInventarioActualizadoPayload.fromJson(
        event.payload,
      );
      if (conflictedEventIds.contains(payload.baseEventId) ||
          await _dependencies.hasFailed(payload.baseEventId)) {
        return const PendingConflict(
          'La actualización depende de otro evento local en conflicto.',
        );
      }
    }
    if (event.eventType == MovimientoInventarioRegistradoPayload.eventType) {
      final payload = MovimientoInventarioRegistradoPayload.fromJson(
        event.payload,
      );
      if (conflictedEventIds.contains(payload.baseEventId) ||
          await _dependencies.hasFailed(payload.baseEventId)) {
        return const PendingConflict(
          'El movimiento depende de otro evento local en conflicto.',
        );
      }
    }
    return null;
  }

  Future<PendingConflict?> _inventoryItemCreadoConflict(SyncEvent event) async {
    final store = _inventoryProjectionStore;
    if (store == null) return null;
    final payload = RecursoInventarioCreadoPayload.fromJson(event.payload);
    final item = await store.findItemById(event.aggregateId);
    if (item != null && item.createdEventId != event.eventId) {
      return PendingConflict(
        'Ya existe un recurso oficial con id ${event.aggregateId}.',
      );
    }
    final movementId = payload.initialMovement?.movementId;
    if (movementId != null) {
      final movement = await store.findMovementById(movementId);
      if (movement != null && movement.eventId != event.eventId) {
        return PendingConflict(
          'Ya existe un movimiento oficial con id $movementId.',
        );
      }
    }
    final unit = await store.findUnitById(payload.defaultUnitId);
    if (unit == null || !unit.active) {
      return const PendingConflict(
        'La unidad del recurso ya no existe o está inactiva.',
      );
    }
    return null;
  }

  Future<PendingConflict?> _inventoryMutationConflict(SyncEvent event) async {
    final store = _inventoryProjectionStore;
    if (store == null) return null;
    final item = await store.findItemById(event.aggregateId);
    if (item == null || !item.active) {
      return const PendingConflict(
        'Ya no existe el recurso de inventario que se intentó modificar.',
      );
    }

    final String baseEventId;
    if (event.eventType == RecursoInventarioActualizadoPayload.eventType) {
      baseEventId = RecursoInventarioActualizadoPayload.fromJson(
        event.payload,
      ).baseEventId;
    } else {
      final payload = MovimientoInventarioRegistradoPayload.fromJson(
        event.payload,
      );
      baseEventId = payload.baseEventId;
      final movement = await store.findMovementById(
        payload.movement.movementId,
      );
      if (movement != null && movement.eventId != event.eventId) {
        return PendingConflict(
          'Ya existe un movimiento oficial con id ${payload.movement.movementId}.',
        );
      }
    }

    final resolvedBase = await _dependencies.resolveBase(
      baseEventId: baseEventId,
      fallbackServerSequence: event.baseServerSequence,
    );
    if (resolvedBase.waitsForLocalDependency) return null;
    final baseServerSequence = resolvedBase.serverSequence;
    if (baseServerSequence == null) return null;

    final officialEvents = await _syncedEventHistory.eventsForAggregateAfter(
      aggregateType: RecursoInventarioCreadoPayload.aggregateType,
      aggregateId: event.aggregateId,
      serverSequence: baseServerSequence,
    );
    final changedOfficially = officialEvents.any(
      (officialEvent) =>
          officialEvent.eventId != event.eventId &&
          (officialEvent.eventType ==
                  RecursoInventarioActualizadoPayload.eventType ||
              officialEvent.eventType ==
                  MovimientoInventarioRegistradoPayload.eventType),
    );
    if (!changedOfficially) return null;
    return const PendingConflict(
      'El recurso de inventario cambió oficialmente desde la base local.',
    );
  }

  @override
  Future<void> restore(SyncEvent event, PendingConflict conflict) async {
    switch (event.eventType) {
      case RecursoInventarioCreadoPayload.eventType:
        await _inventoryProjectionStore?.deleteCreatedByEvent(event.eventId);
      case RecursoInventarioActualizadoPayload.eventType:
        final payload = RecursoInventarioActualizadoPayload.fromJson(
          event.payload,
        );
        await _inventoryProjectionStore?.restoreItemUpdate(
          inventoryItemId: event.aggregateId,
          eventId: event.eventId,
          baseEventId: payload.baseEventId,
          baseVersion: event.baseVersion!,
          baseServerSequence: event.baseServerSequence,
          previousName: payload.previousName,
          nextName: payload.nextName,
        );
      case MovimientoInventarioRegistradoPayload.eventType:
        final payload = MovimientoInventarioRegistradoPayload.fromJson(
          event.payload,
        );
        await _inventoryProjectionStore?.restoreMovement(
          inventoryItemId: event.aggregateId,
          eventId: event.eventId,
          baseEventId: payload.baseEventId,
          baseVersion: event.baseVersion!,
          baseServerSequence: event.baseServerSequence,
          movementId: payload.movement.movementId,
          quantityDeltaAtomic: payload.movement.quantityDeltaAtomic,
        );
    }
  }
}
