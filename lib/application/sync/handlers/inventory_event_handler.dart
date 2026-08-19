import '../models/sync_event.dart';
import '../payloads/recurso_inventario_creado_payload.dart';
import '../projections/inventory_projection_store.dart';

class InventoryEventHandler {
  InventoryEventHandler(this._projectionStore);

  final InventoryProjectionStore _projectionStore;

  Future<void> applyRecursoInventarioCreado(SyncEvent event) async {
    if (event.aggregateType != RecursoInventarioCreadoPayload.aggregateType) {
      throw const FormatException(
        'recurso_inventario_creado debe usar aggregate_type inventory_item.',
      );
    }
    final payload = RecursoInventarioCreadoPayload.fromJson(event.payload);
    if (payload.inventoryItemId != event.aggregateId) {
      throw const FormatException(
        'inventory_item_id no coincide con aggregate_id.',
      );
    }

    final unit = await _projectionStore.findUnitById(payload.defaultUnitId);
    if (unit == null || !unit.active) {
      throw InventoryProjectionConflict(
        'La unidad ${payload.defaultUnitId} no existe o está inactiva.',
      );
    }
    if (!const {'count', 'mass', 'volume'}.contains(unit.dimension) ||
        unit.atomicFactor <= 0 ||
        unit.maxFractionDigits < 0 ||
        unit.maxFractionDigits > 9) {
      throw const FormatException('La configuración de la unidad es inválida.');
    }

    var existing = await _projectionStore.findItemById(event.aggregateId);
    if (existing != null) {
      if (existing.createdEventId != event.eventId) {
        final canReplacePending =
            event.serverSequence != null &&
            existing.lastServerSequence == null &&
            existing.createdEventId != null;
        if (!canReplacePending) {
          throw InventoryProjectionConflict(
            'Ya existe un recurso con id ${event.aggregateId}.',
          );
        }
        await _projectionStore.deleteCreatedByEvent(existing.createdEventId!);
        existing = null;
      } else {
        final serverSequence = event.serverSequence;
        if (serverSequence != null) {
          await _projectionStore.advanceCreationServerSequence(
            inventoryItemId: event.aggregateId,
            eventId: event.eventId,
            serverSequence: serverSequence,
          );
        }
        return;
      }
    }

    final initialMovement = payload.initialMovement;
    if (initialMovement != null) {
      final existingMovement = await _projectionStore.findMovementById(
        initialMovement.movementId,
      );
      if (existingMovement != null) {
        final canReplacePending =
            event.serverSequence != null &&
            existingMovement.serverSequence == null;
        if (!canReplacePending) {
          throw InventoryProjectionConflict(
            'Ya existe un movimiento con id ${initialMovement.movementId}.',
          );
        }
        await _projectionStore.deleteCreatedByEvent(existingMovement.eventId);
      }
    }

    final delta = initialMovement?.quantityDeltaAtomic ?? 0;
    final version = event.baseVersion ?? 1;
    await _projectionStore.insertCreation(
      InventoryCreationProjection(
        item: InventoryItemProjection(
          id: event.aggregateId,
          defaultUnitId: payload.defaultUnitId,
          name: payload.name,
          active: true,
          version: version,
          createdEventId: event.eventId,
          lastEventId: event.eventId,
          lastServerSequence: event.serverSequence,
        ),
        balance: InventoryBalanceProjection(
          inventoryItemId: event.aggregateId,
          quantityOnHandAtomic: delta,
          quantityAvailableAtomic: delta,
          lastEventId: event.eventId,
          lastServerSequence: event.serverSequence,
        ),
        movement: initialMovement == null
            ? null
            : InventoryMovementProjection(
                id: initialMovement.movementId,
                inventoryItemId: event.aggregateId,
                eventId: event.eventId,
                movementType: initialMovement.movementType,
                quantityDeltaAtomic: initialMovement.quantityDeltaAtomic,
                reason: initialMovement.reason,
                createdAtLocal: event.createdAtLocal,
                serverSequence: event.serverSequence,
              ),
      ),
    );
  }
}
