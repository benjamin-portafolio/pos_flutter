import 'payloads/operacion_venta_conciliada_payload.dart';
import 'models/sync_event.dart';
import 'payloads/venta_anulada_payload.dart';
import 'payloads/devolucion_venta_registrada_payload.dart';
import 'payloads/sale_adjustment_payload.dart';
import 'payloads/sale_adjustment_delivery_policy.dart';
import 'synced_event_history.dart';

class SaleAdjustmentSyncContract {
  static bool isCommercial(String type) => [
    VentaAnuladaPayload.eventType,
    DevolucionVentaRegistradaPayload.eventType,
  ].contains(type);
  static bool supports(String type) => [
    OperacionVentaConciliadaPayload.eventType,
    VentaAnuladaPayload.eventType,
    DevolucionVentaRegistradaPayload.eventType,
  ].contains(type);
  static List<String> dependencies(SyncEvent e) =>
      e.eventType == OperacionVentaConciliadaPayload.eventType
      ? OperacionVentaConciliadaPayload.fromJson(e.payload).dependencyEventIds
      : SaleAdjustmentPayload.fromJson(e.payload).dependencyEventIds;
  static int occurredAt(String type, Map<String, Object?> payload) =>
      type == OperacionVentaConciliadaPayload.eventType
      ? OperacionVentaConciliadaPayload.fromJson(payload).occurredAtMs
      : SaleAdjustmentPayload.fromJson(payload).occurredAtMs;
  static Future<Map<String, Object?>> resolve(
    SyncEvent e,
    SyncedEventHistory history,
  ) async {
    final deps = dependencies(e);
    final base = e.eventType == OperacionVentaConciliadaPayload.eventType
        ? OperacionVentaConciliadaPayload.fromJson(
            e.payload,
          ).officialBaseEventId
        : (SaleAdjustmentPayload.fromJson(
                e.payload,
              ).previousAdjustmentEventId ??
              SaleAdjustmentPayload.fromJson(e.payload).confirmationEventId);
    final states = <String, Map<String, Object?>>{};
    for (final id in deps) {
      final d = await history.eventById(id);
      if (d != null) {
        states[id] = {
          'status': d.deliveryStatus == 'delivered'
              ? 'accepted'
              : d.deliveryStatus,
          'server_sequence': d.serverSequence,
        };
      }
    }
    return SaleAdjustmentDeliveryPolicy.resolveBase(base, deps, states);
  }
}
