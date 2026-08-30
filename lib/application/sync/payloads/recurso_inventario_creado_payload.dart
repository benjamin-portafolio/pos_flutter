import '../../../domain/inventario/nombre_recurso_inventario.dart';
import '../../../domain/inventario/tipo_movimiento_inventario.dart';
import 'inventory_movement_payload.dart';

class RecursoInventarioCreadoPayload {
  const RecursoInventarioCreadoPayload({
    required this.inventoryItemId,
    required this.name,
    required this.defaultUnitId,
    required this.initialMovement,
  });

  static const aggregateType = 'inventory_item';
  static const eventType = 'recurso_inventario_creado';

  final String inventoryItemId;
  final String name;
  final String defaultUnitId;
  final InventoryMovementPayload? initialMovement;

  factory RecursoInventarioCreadoPayload.create({
    required String inventoryItemId,
    required String name,
    required String defaultUnitId,
    InventoryMovementPayload? initialMovement,
  }) {
    if (initialMovement != null &&
        initialMovement.movementType !=
            TipoMovimientoInventario.initialBalance) {
      throw const FormatException(
        'Los eventos nuevos deben usar initial_balance para la existencia inicial.',
      );
    }
    return RecursoInventarioCreadoPayload(
      inventoryItemId: InventoryMovementPayload.requiredUuidV4(
        inventoryItemId,
        'inventory_item.inventory_item_id',
      ),
      name: NombreRecursoInventario.fromInput(name).value,
      defaultUnitId: InventoryMovementPayload.requiredUuidV4(
        defaultUnitId,
        'inventory_item.default_unit_id',
      ),
      initialMovement: initialMovement,
    );
  }

  factory RecursoInventarioCreadoPayload.fromJson(Map<String, Object?> json) {
    final item = _requiredMap(json['inventory_item'], 'inventory_item');
    final movementJson = json['initial_movement'];
    final movement = movementJson == null
        ? null
        : InventoryMovementPayload.fromJson(
            _requiredMap(movementJson, 'initial_movement'),
          );
    if (movement != null &&
        movement.movementType != TipoMovimientoInventario.initialBalance &&
        movement.movementType != TipoMovimientoInventario.manualAdjustment) {
      throw const FormatException(
        'initial_movement debe usar initial_balance o manual_adjustment legado.',
      );
    }
    return RecursoInventarioCreadoPayload(
      inventoryItemId: InventoryMovementPayload.requiredUuidV4(
        _requiredString(
          item['inventory_item_id'],
          'inventory_item.inventory_item_id',
        ),
        'inventory_item.inventory_item_id',
      ),
      name: NombreRecursoInventario.fromInput(
        _requiredString(item['name'], 'inventory_item.name'),
      ).value,
      defaultUnitId: InventoryMovementPayload.requiredUuidV4(
        _requiredString(
          item['default_unit_id'],
          'inventory_item.default_unit_id',
        ),
        'inventory_item.default_unit_id',
      ),
      initialMovement: movement,
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
}

typedef InitialInventoryMovementPayload = InventoryMovementPayload;

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
