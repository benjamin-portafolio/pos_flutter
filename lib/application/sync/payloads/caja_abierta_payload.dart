import 'inventory_movement_payload.dart';
import 'movimiento_financiero_registrado_payload.dart';

class CajaAbiertaPayload {
  CajaAbiertaPayload({
    required this.openingMinor,
    required this.openedAtMs,
    this.previousCloseEventId,
  }) {
    cashNonnegative(openingMinor);
    financialOccurredAtMs(openedAtMs);
    if (previousCloseEventId != null) {
      InventoryMovementPayload.requiredUuidV4(
        previousCloseEventId!,
        'previous_close_event_id',
      );
    }
  }
  static const aggregateType = 'cash_session', eventType = 'caja_abierta';
  final int openingMinor, openedAtMs;
  final String? previousCloseEventId;
  List<String> get dependencyEventIds => [?previousCloseEventId];
  factory CajaAbiertaPayload.fromJson(Map<String, Object?> p) =>
      CajaAbiertaPayload(
        openingMinor: p['opening_minor'] as int,
        openedAtMs: p['opened_at_ms'] as int,
        previousCloseEventId: p['previous_close_event_id'] as String?,
      );
  Map<String, Object?> toJson() => {
    'opening_minor': openingMinor,
    'opened_at_ms': openedAtMs,
    'previous_close_event_id': previousCloseEventId,
  };
}

int cashNonnegative(int v) {
  if (v < 0 || v > maxAmountMinor) {
    throw const FormatException('Importe fuera de rango.');
  }
  return v;
}
