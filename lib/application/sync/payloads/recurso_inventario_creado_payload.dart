import '../../../domain/inventario/nombre_recurso_inventario.dart';
import '../../../domain/inventario/tipo_movimiento_inventario.dart';
import 'inventory_movement_payload.dart';

class RecursoInventarioCreadoPayload {
  const RecursoInventarioCreadoPayload({
    required this.inventoryItemId,
    required this.name,
    required this.defaultUnitId,
    required this.initialMovement,
    this.originVariantId,
  });

  static const aggregateType = 'inventory_item';
  static const eventType = 'recurso_inventario_creado';

  /// Clave del origen dentro de `inventory_item`. La comparten este contrato y
  /// los registros, revalidadores y pruebas: no se repite el literal.
  static const originVariantIdField = 'origin_variant_id';

  final String inventoryItemId;
  final String name;
  final String defaultUnitId;
  final InventoryMovementPayload? initialMovement;

  /// Procedencia: variante que originó el recurso. Solo este evento la
  /// establece; editar el nombre o mover stock no la modifica. Es una
  /// identidad, no una FK: el recurso se aplica antes de que exista la
  /// variante. Null significa desconocido (recursos independientes, eventos
  /// legados y `null` explícito).
  final String? originVariantId;

  factory RecursoInventarioCreadoPayload.create({
    required String inventoryItemId,
    required String name,
    required String defaultUnitId,
    InventoryMovementPayload? initialMovement,
    String? originVariantId,
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
      originVariantId: _optionalOriginVariantId(originVariantId),
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
      originVariantId: _readOriginVariantId(item),
    );
  }

  Map<String, Object?> toJson() => {
    'inventory_item': {
      'inventory_item_id': inventoryItemId,
      'name': name,
      'default_unit_id': defaultUnitId,
      // Se omite cuando no hay procedencia: la forma canónica de un recurso
      // independiente o legado no cambia y no se inventa un origen.
      if (originVariantId != null) originVariantIdField: originVariantId,
    },
    'initial_movement': initialMovement?.toJson(),
  };
}

typedef InitialInventoryMovementPayload = InventoryMovementPayload;

String? _optionalOriginVariantId(String? value) {
  if (value == null) return null;
  return InventoryMovementPayload.requiredUuidV4(
    value,
    'inventory_item.'
    '${RecursoInventarioCreadoPayload.originVariantIdField}',
  );
}

/// Ausencia y `null` se leen como desconocido. Un valor presente debe ser un
/// UUID v4; cualquier otra cosa se rechaza en lugar de convertirse en `null`.
String? _readOriginVariantId(Map<String, Object?> item) {
  final raw = item[RecursoInventarioCreadoPayload.originVariantIdField];
  if (raw == null) return null;
  if (raw is! String) {
    throw FormatException(
      'inventory_item.${RecursoInventarioCreadoPayload.originVariantIdField} '
      'debe ser un UUID v4 o null.',
    );
  }
  return InventoryMovementPayload.requiredUuidV4(
    raw,
    'inventory_item.${RecursoInventarioCreadoPayload.originVariantIdField}',
  );
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
