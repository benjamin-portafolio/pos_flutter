import 'dart:convert';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/sale_adjustment_payload.dart';
import '../../sync/payloads/sale_adjustment_rules.dart';
import '../../sync/payloads/sale_adjustment_delivery_policy.dart';
import '../../sync/payloads/venta_confirmada_payload.dart';
import '../../sync/payloads/venta_anulada_payload.dart';
import '../../sync/payloads/devolucion_venta_registrada_payload.dart';

/// Pure preparation only. No service, DI registration, append or remote I/O.
/// Los command services lo ejecutan bajo su transacción antes de append.
class SaleAdjustmentCommandContract {
  static LocalEventAppend prepare({
    required SaleAdjustmentPayload payload,
    required VentaConfirmadaPayload original,
    required String saleId,
    required String confirmationEventId,
    required List<SaleAdjustmentPayload> history,
    required String mode,
    required String userId,
    required String deviceId,
    bool integrationVerified = false,
    int? effectiveBaseServerSequence,
  }) {
    SaleAdjustmentDeliveryPolicy.forMode(
      mode,
      integrationVerified: integrationVerified,
    );
    if (userId.trim().isEmpty ||
        deviceId.trim().isEmpty ||
        payload.expectedRevision >= 9007199254740991 ||
        (effectiveBaseServerSequence != null &&
            (effectiveBaseServerSequence <= 0 ||
                effectiveBaseServerSequence > 9007199254740991))) {
      throw const FormatException('Contexto o base inválidos.');
    }
    SaleAdjustmentRules.validate(
      payload,
      original,
      confirmationEventId: confirmationEventId,
      saleId: saleId,
      history: history,
    );
    final refs = SaleAdjustmentRules.refs(
      payload,
      original,
    ); // validate in BOTH modes
    return LocalEventAppend(
      event: intention(
        payload: payload,
        mode: mode,
        userId: userId,
        deviceId: deviceId,
        integrationVerified: integrationVerified,
        effectiveBaseServerSequence: effectiveBaseServerSequence,
      ),
      refs: refs,
    );
  }

  /// Construye el sobre congelado antes de consultar revisiones para reintentos.
  static SyncEvent intention({
    required SaleAdjustmentPayload payload,
    required String mode,
    required String userId,
    required String deviceId,
    bool integrationVerified = false,
    int? effectiveBaseServerSequence,
  }) {
    final policy = SaleAdjustmentDeliveryPolicy.forMode(
      mode,
      integrationVerified: integrationVerified,
    );
    return SyncEvent(
      eventId: payload.eventId,
      aggregateType: VentaAnuladaPayload.aggregateType,
      aggregateId: payload.saleId,
      eventType: payload.kind == 'void'
          ? VentaAnuladaPayload.eventType
          : DevolucionVentaRegistradaPayload.eventType,
      deviceId: deviceId,
      userId: userId,
      createdAtLocal: DateTime.fromMillisecondsSinceEpoch(
        payload.occurredAtMs,
        isUtc: true,
      ),
      baseVersion: payload.expectedRevision + 1,
      baseServerSequence: mode == 'standalone'
          ? null
          : effectiveBaseServerSequence,
      payload: payload.toJson(),
      deliveryStatus: policy['delivery_status'] as String,
    );
  }

  /// Use BEFORE base/revision revalidation for retry lookup. A duplicate returns
  /// its ORIGINAL accepted/conflict/rejected result, never a second execution.
  static bool sameIntention(SyncEvent a, SyncEvent b) =>
      a.eventId == b.eventId &&
      a.aggregateId == b.aggregateId &&
      a.aggregateType == b.aggregateType &&
      a.eventType == b.eventType &&
      a.userId == b.userId &&
      a.deviceId == b.deviceId &&
      a.createdAtLocal.millisecondsSinceEpoch ==
          b.createdAtLocal.millisecondsSinceEpoch &&
      a.baseVersion == b.baseVersion &&
      jsonEncode(_canonical(a.payload)) == jsonEncode(_canonical(b.payload));
  static Object? _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return {for (final k in keys) k: _canonical(v[k])};
    }
    if (v is List) return v.map(_canonical).toList();
    return v;
  }
}
