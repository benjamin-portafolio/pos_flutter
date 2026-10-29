import '../models/sale_incident_details.dart';
import '../models/sync_event.dart';
import '../payloads/operacion_venta_conciliada_payload.dart';

abstract interface class SaleReconciliationStore {
  Future<T> atomic<T>(Future<T> Function() action);
  Future<SaleIncidentDetails?> incident(String id);
  Future<SyncEvent?> existing(String operationId, String eventId);
  Future<void> reserveIntention(SyncEvent event);
  Future<void> validate(
    OperacionVentaConciliadaPayload payload, {
    required String deviceId,
  });
  Future<void> apply(
    SyncEvent event,
    OperacionVentaConciliadaPayload payload, {
    required bool official,
  });
  Future<void> acknowledge(SyncEvent event);
}
