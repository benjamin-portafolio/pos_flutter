import 'inventory_movement_payload.dart';
import 'movimiento_financiero_registrado_payload.dart';

class CashMovementEvidence {
  CashMovementEvidence({
    required this.movementId,
    required this.eventId,
    required this.direction,
    required this.amountMinor,
    required this.sourceType,
    required this.sourceId,
  }) {
    for (final id in [movementId, eventId, sourceId]) {
      InventoryMovementPayload.requiredUuidV4(id, 'movement');
    }
    financialAmountMinor(amountMinor);
    if (!['in', 'out'].contains(direction) ||
        ![
          'sale_payment',
          'customer_payment',
          'financial_entry',
        ].contains(sourceType) ||
        (sourceType != 'financial_entry' && direction != 'in')) {
      throw const FormatException('Origen o dirección de caja inválidos.');
    }
  }
  final String movementId, eventId, direction, sourceType, sourceId;
  final int amountMinor;
  factory CashMovementEvidence.fromJson(Map<String, Object?> p) =>
      CashMovementEvidence(
        movementId: p['movement_id'] as String,
        eventId: p['event_id'] as String,
        direction: p['direction'] as String,
        amountMinor: p['amount_minor'] as int,
        sourceType: p['source_type'] as String,
        sourceId: p['source_id'] as String,
      );
  Map<String, Object?> toJson() => {
    'movement_id': movementId,
    'event_id': eventId,
    'direction': direction,
    'amount_minor': amountMinor,
    'source_type': sourceType,
    'source_id': sourceId,
  };
}
