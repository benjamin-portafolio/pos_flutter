import '../models/sync_event.dart';
import '../payloads/inventory_movement_payload.dart';
import '../payloads/movimiento_inventario_registrado_payload.dart';
import '../payloads/recurso_inventario_actualizado_payload.dart';
import '../payloads/recurso_inventario_creado_payload.dart';
import '../projections/inventory_projection_store.dart';

class InventoryEventHandler {
  InventoryEventHandler(this._projectionStore);

  final InventoryProjectionStore _projectionStore;

  Future<void> applyRecursoInventarioCreado(SyncEvent event) async {
    _validateAggregate(event);
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
          version: 1,
          lastEventId: event.eventId,
          lastServerSequence: event.serverSequence,
        ),
        movement: initialMovement == null
            ? null
            : InventoryMovementProjection(
                id: initialMovement.movementId,
                inventoryItemId: event.aggregateId,
                eventId: event.eventId,
                movementType: initialMovement.movementType.code,
                quantityDeltaAtomic: initialMovement.quantityDeltaAtomic,
                reason: initialMovement.reason,
                reversalOfMovementId: initialMovement.reversalOfMovementId,
                totalCostMinor: null,
                createdAtLocal: event.createdAtLocal,
                serverSequence: event.serverSequence,
              ),
      ),
    );
  }

  Future<void> applyRecursoInventarioActualizado(SyncEvent event) async {
    _validateAggregate(event);
    final payload = RecursoInventarioActualizadoPayload.fromJson(event.payload);
    final existing = await _requiredCurrentItem(event.aggregateId);
    if (existing.lastEventId == event.eventId) {
      await _advanceEcho(event, includesBalance: false);
      return;
    }
    _validateBase(event, payload.baseEventId, existing);
    if (existing.name != payload.previousName) {
      throw const InventoryProjectionConflict(
        'El nombre cambió desde la base de la edición.',
      );
    }
    await _projectionStore.applyItemUpdate(
      item: InventoryItemProjection(
        id: existing.id,
        defaultUnitId: existing.defaultUnitId,
        name: payload.nextName,
        active: existing.active,
        version: existing.version + 1,
        createdEventId: existing.createdEventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence ?? existing.lastServerSequence,
      ),
      expectedBaseEventId: payload.baseEventId,
      expectedBaseVersion: event.baseVersion!,
    );
  }

  Future<void> applyMovimientoInventarioRegistrado(SyncEvent event) async {
    _validateAggregate(event);
    final payload = MovimientoInventarioRegistradoPayload.fromJson(
      event.payload,
    );
    final existingMovement = await _projectionStore.findMovementById(
      payload.movement.movementId,
    );
    if (existingMovement != null) {
      if (existingMovement.eventId != event.eventId) {
        throw InventoryProjectionConflict(
          'Ya existe el movimiento ${payload.movement.movementId}.',
        );
      }
      await _advanceEcho(event, includesBalance: true);
      return;
    }

    final item = await _requiredCurrentItem(event.aggregateId);
    _validateBase(event, payload.baseEventId, item);
    final balance = await _projectionStore.findBalanceByItemId(item.id);
    if (balance == null) {
      throw const InventoryProjectionConflict(
        'El recurso no tiene un saldo materializado.',
      );
    }
    final onHand = _safeAdd(
      balance.quantityOnHandAtomic,
      payload.movement.quantityDeltaAtomic,
    );
    final available = _safeAdd(
      balance.quantityAvailableAtomic,
      payload.movement.quantityDeltaAtomic,
    );

    await _projectionStore.applyMovement(
      item: InventoryItemProjection(
        id: item.id,
        defaultUnitId: item.defaultUnitId,
        name: item.name,
        active: item.active,
        version: item.version + 1,
        createdEventId: item.createdEventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence ?? item.lastServerSequence,
      ),
      balance: InventoryBalanceProjection(
        inventoryItemId: balance.inventoryItemId,
        quantityOnHandAtomic: onHand,
        quantityAvailableAtomic: available,
        version: balance.version + 1,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence ?? balance.lastServerSequence,
      ),
      movement: InventoryMovementProjection(
        id: payload.movement.movementId,
        inventoryItemId: item.id,
        eventId: event.eventId,
        movementType: payload.movement.movementType.code,
        quantityDeltaAtomic: payload.movement.quantityDeltaAtomic,
        reason: payload.movement.reason,
        reversalOfMovementId: payload.movement.reversalOfMovementId,
        totalCostMinor: null,
        createdAtLocal: event.createdAtLocal,
        serverSequence: event.serverSequence,
      ),
      expectedBaseEventId: payload.baseEventId,
      expectedBaseVersion: event.baseVersion!,
    );
  }

  Future<InventoryItemProjection> _requiredCurrentItem(String id) async {
    final item = await _projectionStore.findItemById(id);
    if (item == null || !item.active) {
      throw const InventoryProjectionConflict(
        'El recurso de inventario no existe o está inactivo.',
      );
    }
    return item;
  }

  void _validateAggregate(SyncEvent event) {
    if (event.aggregateType != RecursoInventarioCreadoPayload.aggregateType) {
      throw FormatException(
        '${event.eventType} debe usar aggregate_type inventory_item.',
      );
    }
  }

  void _validateBase(
    SyncEvent event,
    String payloadBaseEventId,
    InventoryItemProjection existing,
  ) {
    final baseVersion = event.baseVersion;
    if (baseVersion == null || baseVersion < 1) {
      throw const FormatException('El evento requiere base_version >= 1.');
    }
    if (existing.lastEventId != payloadBaseEventId ||
        existing.version != baseVersion) {
      throw const InventoryProjectionConflict(
        'El recurso cambió desde la base del evento.',
      );
    }
    final baseSequence = event.baseServerSequence;
    if (baseSequence != null && existing.lastServerSequence != baseSequence) {
      throw const InventoryProjectionConflict(
        'La secuencia base no coincide con el recurso.',
      );
    }
  }

  int _safeAdd(int current, int delta) {
    final result = current + delta;
    if (result > InventoryMovementPayload.maxSafeInteger ||
        result < -InventoryMovementPayload.maxSafeInteger) {
      throw const FormatException('El saldo de inventario se desbordaría.');
    }
    return result;
  }

  Future<void> _advanceEcho(
    SyncEvent event, {
    required bool includesBalance,
  }) async {
    final serverSequence = event.serverSequence;
    if (serverSequence == null) return;
    await _projectionStore.advanceEventServerSequence(
      inventoryItemId: event.aggregateId,
      eventId: event.eventId,
      serverSequence: serverSequence,
      includesBalance: includesBalance,
    );
  }
}
