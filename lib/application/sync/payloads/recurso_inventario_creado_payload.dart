import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../domain/inventario/nombre_recurso_inventario.dart';

class RecursoInventarioCreadoPayload {
  const RecursoInventarioCreadoPayload({
    required this.inventoryItemId,
    required this.name,
    required this.defaultUnitId,
    required this.initialMovement,
  });

  static const aggregateType = 'inventory_item';
  static const eventType = 'recurso_inventario_creado';
  static const _maxSafeInteger = 9007199254740991;

  final String inventoryItemId;
  final String name;
  final String defaultUnitId;
  final InitialInventoryMovementPayload? initialMovement;

  factory RecursoInventarioCreadoPayload.create({
    required String inventoryItemId,
    required String name,
    required String defaultUnitId,
    InitialInventoryMovementPayload? initialMovement,
  }) {
    return RecursoInventarioCreadoPayload(
      inventoryItemId: _requiredUuidV4(
        inventoryItemId,
        'inventory_item.inventory_item_id',
      ),
      name: NombreRecursoInventario.fromInput(name).value,
      defaultUnitId: _requiredUuidV4(
        defaultUnitId,
        'inventory_item.default_unit_id',
      ),
      initialMovement: initialMovement,
    );
  }

  factory RecursoInventarioCreadoPayload.fromJson(Map<String, Object?> json) {
    final item = _requiredMap(json['inventory_item'], 'inventory_item');
    final movementJson = json['initial_movement'];
    return RecursoInventarioCreadoPayload.create(
      inventoryItemId: _requiredString(
        item['inventory_item_id'],
        'inventory_item.inventory_item_id',
      ),
      name: _requiredString(item['name'], 'inventory_item.name'),
      defaultUnitId: _requiredString(
        item['default_unit_id'],
        'inventory_item.default_unit_id',
      ),
      initialMovement: movementJson == null
          ? null
          : InitialInventoryMovementPayload.fromJson(
              _requiredMap(movementJson, 'initial_movement'),
            ),
    );
  }

  Map<String, Object?> toJson() => {
    'inventory_item': {
      'inventory_item_id': inventoryItemId,
      'name': name,
      'default_unit_id': defaultUnitId,
    },
    'initial_movement': initialMovement?.toJson(),
  };

  static int validateAtomicDelta(Object? value) {
    if (value is! int ||
        value == 0 ||
        value > _maxSafeInteger ||
        value < -_maxSafeInteger) {
      throw const FormatException(
        'initial_movement.quantity_delta_atomic debe ser un entero seguro distinto de cero.',
      );
    }
    return value;
  }
}

class InitialInventoryMovementPayload {
  const InitialInventoryMovementPayload({
    required this.movementId,
    required this.movementType,
    required this.quantityDeltaAtomic,
    required this.reason,
  });

  factory InitialInventoryMovementPayload.create({
    required String movementId,
    required int quantityDeltaAtomic,
    required String reason,
  }) {
    final normalizedReason = unorm.nfkc(reason).trim();
    if (normalizedReason.isEmpty || normalizedReason.runes.length > 500) {
      throw const FormatException(
        'El motivo del movimiento debe tener entre 1 y 500 caracteres.',
      );
    }
    return InitialInventoryMovementPayload(
      movementId: _requiredUuidV4(movementId, 'initial_movement.movement_id'),
      movementType: 'manual_adjustment',
      quantityDeltaAtomic: RecursoInventarioCreadoPayload.validateAtomicDelta(
        quantityDeltaAtomic,
      ),
      reason: normalizedReason,
    );
  }

  factory InitialInventoryMovementPayload.fromJson(Map<String, Object?> json) {
    if (json['movement_type'] != 'manual_adjustment') {
      throw const FormatException(
        'El movimiento inicial debe usar manual_adjustment.',
      );
    }
    return InitialInventoryMovementPayload.create(
      movementId: _requiredString(
        json['movement_id'],
        'initial_movement.movement_id',
      ),
      quantityDeltaAtomic: RecursoInventarioCreadoPayload.validateAtomicDelta(
        json['quantity_delta_atomic'],
      ),
      reason: _requiredString(json['reason'], 'initial_movement.reason'),
    );
  }

  final String movementId;
  final String movementType;
  final int quantityDeltaAtomic;
  final String reason;

  Map<String, Object?> toJson() => {
    'movement_id': movementId,
    'movement_type': movementType,
    'quantity_delta_atomic': quantityDeltaAtomic,
    'reason': reason,
  };
}

Map<String, Object?> _requiredMap(Object? value, String fieldName) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('$fieldName debe ser un objeto.');
}

String _requiredString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName es obligatorio.');
  }
  return value.trim();
}

String _requiredUuidV4(String value, String fieldName) {
  final normalized = value.trim();
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    throw FormatException('$fieldName debe ser un UUID v4.');
  }
  return normalized;
}
