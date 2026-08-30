import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../../domain/inventario/tipo_movimiento_inventario.dart';

class InventoryMovementPayload {
  const InventoryMovementPayload._({
    required this.movementId,
    required this.movementType,
    required this.quantityDeltaAtomic,
    required this.reason,
    required this.reversalOfMovementId,
  });

  static const maxSafeInteger = 9007199254740991;

  final String movementId;
  final TipoMovimientoInventario movementType;
  final int quantityDeltaAtomic;
  final String? reason;
  final String? reversalOfMovementId;

  factory InventoryMovementPayload.create({
    required String movementId,
    required TipoMovimientoInventario movementType,
    required int quantityDeltaAtomic,
    String? reason,
    String? reversalOfMovementId,
  }) {
    return _validated(
      movementId: movementId,
      movementType: movementType,
      quantityDeltaAtomic: quantityDeltaAtomic,
      reason: reason,
      reversalOfMovementId: reversalOfMovementId,
      emptyReasonAsNull: true,
    );
  }

  factory InventoryMovementPayload.fromJson(Map<String, Object?> json) {
    final movementType = TipoMovimientoInventario.fromCode(
      _requiredString(json['movement_type'], 'movement.movement_type'),
    );
    final reversal = json['reversal_of_movement_id'];
    if (reversal != null && reversal is! String) {
      throw const FormatException(
        'movement.reversal_of_movement_id debe ser UUID v4 o null.',
      );
    }
    final reason = json['reason'];
    if (reason != null && reason is! String) {
      throw const FormatException('movement.reason debe ser texto o null.');
    }
    return _validated(
      movementId: _requiredString(json['movement_id'], 'movement.movement_id'),
      movementType: movementType,
      quantityDeltaAtomic: validateAtomicDelta(json['quantity_delta_atomic']),
      reason: reason as String?,
      reversalOfMovementId: reversal as String?,
      emptyReasonAsNull: false,
    );
  }

  static InventoryMovementPayload _validated({
    required String movementId,
    required TipoMovimientoInventario movementType,
    required int quantityDeltaAtomic,
    required String? reason,
    required String? reversalOfMovementId,
    required bool emptyReasonAsNull,
  }) {
    final normalizedMovementId = requiredUuidV4(
      movementId,
      'movement.movement_id',
    );
    validateAtomicDelta(quantityDeltaAtomic);
    final normalizedReason = normalizeReason(
      reason,
      emptyAsNull: emptyReasonAsNull,
    );
    final normalizedReversal = reversalOfMovementId == null
        ? null
        : requiredUuidV4(
            reversalOfMovementId,
            'movement.reversal_of_movement_id',
          );

    switch (movementType) {
      case TipoMovimientoInventario.initialBalance:
      case TipoMovimientoInventario.stockReceipt:
        if (quantityDeltaAtomic <= 0) {
          throw FormatException(
            '${movementType.code} requiere un delta positivo.',
          );
        }
      case TipoMovimientoInventario.manualAdjustment:
        if (normalizedReason == null) {
          throw const FormatException('manual_adjustment requiere un motivo.');
        }
      case TipoMovimientoInventario.reversal:
        if (normalizedReversal == null) {
          throw const FormatException(
            'reversal requiere reversal_of_movement_id.',
          );
        }
    }

    if (movementType != TipoMovimientoInventario.reversal &&
        normalizedReversal != null) {
      throw const FormatException(
        'Solo reversal admite reversal_of_movement_id.',
      );
    }
    if (normalizedReversal == normalizedMovementId) {
      throw const FormatException(
        'Un movimiento no puede revertirse a sí mismo.',
      );
    }

    return InventoryMovementPayload._(
      movementId: normalizedMovementId,
      movementType: movementType,
      quantityDeltaAtomic: quantityDeltaAtomic,
      reason: normalizedReason,
      reversalOfMovementId: normalizedReversal,
    );
  }

  Map<String, Object?> toJson() => {
    'movement_id': movementId,
    'movement_type': movementType.code,
    'quantity_delta_atomic': quantityDeltaAtomic,
    'reason': reason,
    'reversal_of_movement_id': reversalOfMovementId,
    'total_cost_minor': null,
  };

  static int validateAtomicDelta(Object? value) {
    if (value is! int ||
        value == 0 ||
        value > maxSafeInteger ||
        value < -maxSafeInteger) {
      throw const FormatException(
        'movement.quantity_delta_atomic debe ser un entero seguro distinto de cero.',
      );
    }
    return value;
  }

  static String? normalizeReason(String? value, {bool emptyAsNull = true}) {
    if (value == null) return null;
    final normalized = unorm.nfkc(value).trim();
    if (normalized.isEmpty) {
      if (emptyAsNull) return null;
      throw const FormatException(
        'movement.reason presente debe tener entre 1 y 500 caracteres.',
      );
    }
    if (normalized.runes.length > 500) {
      throw const FormatException(
        'movement.reason presente debe tener entre 1 y 500 caracteres.',
      );
    }
    return normalized;
  }

  static String requiredUuidV4(String value, String fieldName) {
    final normalized = value.trim();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(normalized)) {
      throw FormatException('$fieldName debe ser un UUID v4.');
    }
    return normalized;
  }
}

String _requiredString(Object? value, String fieldName) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName es obligatorio.');
  }
  return value.trim();
}
