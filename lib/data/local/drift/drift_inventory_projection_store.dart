import 'package:drift/drift.dart' as drift;

import '../../../application/sync/projections/inventory_projection_store.dart';
import 'app_database.dart' as local;

class DriftInventoryProjectionStore implements InventoryProjectionStore {
  DriftInventoryProjectionStore({
    required local.InventoryDao inventoryDao,
    required local.UnitDao unitDao,
  }) : _inventoryDao = inventoryDao,
       _unitDao = unitDao;

  final local.InventoryDao _inventoryDao;
  final local.UnitDao _unitDao;

  @override
  Future<InventoryUnitProjection?> findUnitById(String unitId) async {
    final row = await _unitDao.obtenerUnidadPorId(unitId);
    return row == null
        ? null
        : InventoryUnitProjection(
            id: row.unitId,
            dimension: row.dimension,
            atomicFactor: row.atomicFactor,
            maxFractionDigits: row.maxFractionDigits,
            active: row.active,
          );
  }

  @override
  Future<InventoryItemProjection?> findItemById(String id) async {
    final row = await _inventoryDao.obtenerRecursoPorId(id);
    return row == null
        ? null
        : InventoryItemProjection(
            id: row.id,
            defaultUnitId: row.defaultUnitId,
            name: row.name,
            active: row.active,
            version: row.version,
            createdEventId: row.createdEventId,
            lastEventId: row.lastEventId,
            lastServerSequence: row.lastServerSequence,
          );
  }

  @override
  Future<InventoryMovementProjection?> findMovementById(String id) async {
    final row = await _inventoryDao.obtenerMovimientoPorId(id);
    return row == null
        ? null
        : InventoryMovementProjection(
            id: row.movementId,
            inventoryItemId: row.inventoryItemId,
            eventId: row.eventId,
            movementType: row.movementType,
            quantityDeltaAtomic: row.quantityDeltaAtomic,
            reason: row.reason,
            reversalOfMovementId: row.reversalOfMovementId,
            totalCostMinor: row.totalCostMinor,
            createdAtLocal: row.createdAtLocal,
            serverSequence: row.serverSequence,
          );
  }

  @override
  Future<void> insertCreation(InventoryCreationProjection creation) {
    final item = creation.item;
    final balance = creation.balance;
    final movement = creation.movement;
    return _inventoryDao.insertarCreacion(
      item: local.InventoryItemsCompanion.insert(
        id: item.id,
        defaultUnitId: item.defaultUnitId,
        name: item.name,
        active: drift.Value(item.active),
        version: drift.Value(item.version),
        createdEventId: drift.Value(item.createdEventId),
        lastEventId: drift.Value(item.lastEventId),
        lastServerSequence: drift.Value(item.lastServerSequence),
      ),
      balance: local.InventoryBalancesCompanion.insert(
        inventoryItemId: balance.inventoryItemId,
        quantityOnHandAtomic: balance.quantityOnHandAtomic,
        quantityAvailableAtomic: balance.quantityAvailableAtomic,
        version: drift.Value(balance.version),
        lastEventId: balance.lastEventId,
        lastServerSequence: drift.Value(balance.lastServerSequence),
      ),
      movement: movement == null
          ? null
          : local.InventoryMovementsCompanion.insert(
              movementId: movement.id,
              inventoryItemId: movement.inventoryItemId,
              eventId: movement.eventId,
              movementType: movement.movementType,
              quantityDeltaAtomic: movement.quantityDeltaAtomic,
              reversalOfMovementId: drift.Value(movement.reversalOfMovementId),
              totalCostMinor: drift.Value(movement.totalCostMinor),
              reason: drift.Value(movement.reason),
              createdAtLocal: movement.createdAtLocal,
              serverSequence: drift.Value(movement.serverSequence),
            ),
    );
  }

  @override
  Future<InventoryBalanceProjection?> findBalanceByItemId(String id) async {
    final row = await _inventoryDao.obtenerSaldoPorRecursoId(id);
    return row == null
        ? null
        : InventoryBalanceProjection(
            inventoryItemId: row.inventoryItemId,
            quantityOnHandAtomic: row.quantityOnHandAtomic,
            quantityAvailableAtomic: row.quantityAvailableAtomic,
            version: row.version,
            lastEventId: row.lastEventId,
            lastServerSequence: row.lastServerSequence,
          );
  }

  @override
  Future<void> applyItemUpdate({
    required InventoryItemProjection item,
    required String expectedBaseEventId,
    required int expectedBaseVersion,
  }) {
    return _inventoryDao.actualizarRecurso(
      item: local.InventoryItemsCompanion(
        name: drift.Value(item.name),
        version: drift.Value(item.version),
        lastEventId: drift.Value(item.lastEventId),
        lastServerSequence: drift.Value(item.lastServerSequence),
      ),
      inventoryItemId: item.id,
      expectedBaseEventId: expectedBaseEventId,
      expectedBaseVersion: expectedBaseVersion,
    );
  }

  @override
  Future<void> applyMovement({
    required InventoryItemProjection item,
    required InventoryBalanceProjection balance,
    required InventoryMovementProjection movement,
    required String expectedBaseEventId,
    required int expectedBaseVersion,
  }) {
    return _inventoryDao.registrarMovimiento(
      item: local.InventoryItemsCompanion(
        version: drift.Value(item.version),
        lastEventId: drift.Value(item.lastEventId),
        lastServerSequence: drift.Value(item.lastServerSequence),
      ),
      balance: local.InventoryBalancesCompanion(
        quantityOnHandAtomic: drift.Value(balance.quantityOnHandAtomic),
        quantityAvailableAtomic: drift.Value(balance.quantityAvailableAtomic),
        version: drift.Value(balance.version),
        lastEventId: drift.Value(balance.lastEventId),
        lastServerSequence: drift.Value(balance.lastServerSequence),
      ),
      movement: local.InventoryMovementsCompanion.insert(
        movementId: movement.id,
        inventoryItemId: movement.inventoryItemId,
        eventId: movement.eventId,
        reversalOfMovementId: drift.Value(movement.reversalOfMovementId),
        movementType: movement.movementType,
        quantityDeltaAtomic: movement.quantityDeltaAtomic,
        totalCostMinor: drift.Value(movement.totalCostMinor),
        reason: drift.Value(movement.reason),
        createdAtLocal: movement.createdAtLocal,
        serverSequence: drift.Value(movement.serverSequence),
      ),
      inventoryItemId: item.id,
      expectedBaseEventId: expectedBaseEventId,
      expectedBaseVersion: expectedBaseVersion,
    );
  }

  @override
  Future<void> advanceEventServerSequence({
    required String inventoryItemId,
    required String eventId,
    required int serverSequence,
    required bool includesBalance,
  }) {
    return _inventoryDao.avanzarSecuenciaEvento(
      inventoryItemId: inventoryItemId,
      eventId: eventId,
      serverSequence: serverSequence,
      includesBalance: includesBalance,
    );
  }

  @override
  Future<void> advanceCreationServerSequence({
    required String inventoryItemId,
    required String eventId,
    required int serverSequence,
  }) {
    return _inventoryDao.avanzarSecuenciaCreacion(
      inventoryItemId: inventoryItemId,
      eventId: eventId,
      serverSequence: serverSequence,
    );
  }

  @override
  Future<void> restoreItemUpdate({
    required String inventoryItemId,
    required String eventId,
    required String baseEventId,
    required int baseVersion,
    required int? baseServerSequence,
    required String previousName,
    required String nextName,
  }) {
    return _inventoryDao.restaurarActualizacionRecurso(
      inventoryItemId: inventoryItemId,
      eventId: eventId,
      baseEventId: baseEventId,
      baseVersion: baseVersion,
      baseServerSequence: baseServerSequence,
      previousName: previousName,
      nextName: nextName,
    );
  }

  @override
  Future<void> restoreMovement({
    required String inventoryItemId,
    required String eventId,
    required String baseEventId,
    required int baseVersion,
    required int? baseServerSequence,
    required String movementId,
    required int quantityDeltaAtomic,
  }) {
    return _inventoryDao.restaurarMovimiento(
      inventoryItemId: inventoryItemId,
      eventId: eventId,
      baseEventId: baseEventId,
      baseVersion: baseVersion,
      baseServerSequence: baseServerSequence,
      movementId: movementId,
      quantityDeltaAtomic: quantityDeltaAtomic,
    );
  }

  @override
  Future<void> deleteCreatedByEvent(String eventId) {
    return _inventoryDao.eliminarCreacionPorEvento(eventId);
  }
}
