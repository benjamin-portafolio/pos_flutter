import 'package:unorm_dart/unorm_dart.dart' as unorm;

class ExistenciaInventarioAjustadaPayload {
  const ExistenciaInventarioAjustadaPayload._({
    required this.inventoryItemId,
    required this.movementId,
    required this.quantityDeltaAtomic,
    required this.reason,
  });

  static const aggregateType = 'inventory_item';
  static const eventType = 'existencia_inventario_ajustada';
  static const _maxSafeInteger = 9007199254740991;

  factory ExistenciaInventarioAjustadaPayload.create({
    required String inventoryItemId,
    required String movementId,
    required int quantityDeltaAtomic,
    required String reason,
  }) {
    final normalizedReason = unorm.nfkc(reason).trim();
    if (quantityDeltaAtomic == 0 ||
        quantityDeltaAtomic.abs() > _maxSafeInteger) {
      throw const FormatException(
        'El ajuste debe ser un entero seguro distinto de cero.',
      );
    }
    if (normalizedReason.isEmpty || normalizedReason.runes.length > 500) {
      throw const FormatException(
        'El motivo del ajuste debe tener entre 1 y 500 caracteres.',
      );
    }
    return ExistenciaInventarioAjustadaPayload._(
      inventoryItemId: _requiredUuidV4(inventoryItemId, 'inventory_item_id'),
      movementId: _requiredUuidV4(movementId, 'movement_id'),
      quantityDeltaAtomic: quantityDeltaAtomic,
      reason: normalizedReason,
    );
  }

  factory ExistenciaInventarioAjustadaPayload.fromJson(
    Map<String, Object?> json,
  ) {
    final movement = json['movement'];
    if (movement is! Map) {
      throw const FormatException('movement debe ser un objeto.');
    }
    final movementJson = movement.cast<String, Object?>();
    if (movementJson['movement_type'] != 'manual_adjustment') {
      throw const FormatException(
        'movement.movement_type debe ser manual_adjustment.',
      );
    }
    final delta = movementJson['quantity_delta_atomic'];
    if (delta is! int) {
      throw const FormatException(
        'movement.quantity_delta_atomic debe ser entero.',
      );
    }
    final reason = movementJson['reason'];
    if (reason is! String) {
      throw const FormatException('movement.reason debe ser texto.');
    }
    return ExistenciaInventarioAjustadaPayload.create(
      inventoryItemId: _requiredString(
        json['inventory_item_id'],
        'inventory_item_id',
      ),
      movementId: _requiredString(
        movementJson['movement_id'],
        'movement.movement_id',
      ),
      quantityDeltaAtomic: delta,
      reason: reason,
    );
  }

  final String inventoryItemId;
  final String movementId;
  final int quantityDeltaAtomic;
  final String reason;

  Map<String, Object?> toJson() => {
    'inventory_item_id': inventoryItemId,
    'movement': {
      'movement_id': movementId,
      'movement_type': 'manual_adjustment',
      'quantity_delta_atomic': quantityDeltaAtomic,
      'reason': reason,
    },
  };
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
    throw FormatException('$fieldName debe ser UUID v4.');
  }
  return normalized;
}
