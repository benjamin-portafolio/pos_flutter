import 'sync_projection.dart';

abstract interface class InventoryProjectionStore {
  Future<InventoryUnitProjection?> findUnitById(String unitId);

  Future<InventoryItemProjection?> findItemById(String id);

  Future<InventoryMovementProjection?> findMovementById(String id);

  Future<void> insertCreation(InventoryCreationProjection creation);

  Future<void> advanceCreationServerSequence({
    required String inventoryItemId,
    required String eventId,
    required int serverSequence,
  });

  Future<void> deleteCreatedByEvent(String eventId);
}

class InventoryUnitProjection {
  const InventoryUnitProjection({
    required this.id,
    required this.dimension,
    required this.atomicFactor,
    required this.maxFractionDigits,
    required this.active,
  });

  final String id;
  final String dimension;
  final int atomicFactor;
  final int maxFractionDigits;
  final bool active;
}

class InventoryItemProjection extends SyncProjection {
  const InventoryItemProjection({
    required super.id,
    required this.defaultUnitId,
    required this.name,
    required super.active,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  });

  final String defaultUnitId;
  final String name;
}

class InventoryBalanceProjection {
  const InventoryBalanceProjection({
    required this.inventoryItemId,
    required this.quantityOnHandAtomic,
    required this.quantityAvailableAtomic,
    required this.lastEventId,
    required this.lastServerSequence,
  });

  final String inventoryItemId;
  final int quantityOnHandAtomic;
  final int quantityAvailableAtomic;
  final String lastEventId;
  final int? lastServerSequence;
}

class InventoryMovementProjection {
  const InventoryMovementProjection({
    required this.id,
    required this.inventoryItemId,
    required this.eventId,
    required this.movementType,
    required this.quantityDeltaAtomic,
    required this.reason,
    required this.createdAtLocal,
    required this.serverSequence,
  });

  final String id;
  final String inventoryItemId;
  final String eventId;
  final String movementType;
  final int quantityDeltaAtomic;
  final String reason;
  final DateTime createdAtLocal;
  final int? serverSequence;
}

class InventoryCreationProjection {
  const InventoryCreationProjection({
    required this.item,
    required this.balance,
    required this.movement,
  });

  final InventoryItemProjection item;
  final InventoryBalanceProjection balance;
  final InventoryMovementProjection? movement;
}

class InventoryProjectionConflict implements Exception {
  const InventoryProjectionConflict(this.message);

  final String message;

  @override
  String toString() => message;
}
