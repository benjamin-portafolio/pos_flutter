import '../local_event_store.dart';
import 'inventory_movement_payload.dart';

/// Asociación explícita. Ausencia significa evento histórico/sin caja.
class CashBindingPayload {
  CashBindingPayload({
    required this.sessionId,
    required this.openingEventId,
    required this.movementId,
  }) {
    for (final id in [sessionId, openingEventId, movementId]) {
      InventoryMovementPayload.requiredUuidV4(id, 'cash');
    }
  }
  final String sessionId, openingEventId, movementId;
  static CashBindingPayload? optional(
    Object? value,
    String method,
    int amount,
  ) {
    if (value == null) return null;
    if (method != 'cash' || amount <= 0 || value is! Map) {
      throw const FormatException(
        'Solo efectivo aplicado positivo puede afectar la caja.',
      );
    }
    return CashBindingPayload(
      sessionId: value['session_id'] as String,
      openingEventId: value['opening_event_id'] as String,
      movementId: value['movement_id'] as String,
    );
  }

  Map<String, Object?> toJson() => {
    'session_id': sessionId,
    'opening_event_id': openingEventId,
    'movement_id': movementId,
  };
  List<LocalEventRef> get refs => [
    LocalEventRef.uses(refType: 'cash_session', refId: sessionId),
    LocalEventRef.affects(refType: 'cash_movement', refId: movementId),
  ];
}
