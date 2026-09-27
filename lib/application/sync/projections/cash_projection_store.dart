import '../models/sync_event.dart';
import '../payloads/caja_abierta_payload.dart';
import '../payloads/caja_cerrada_payload.dart';
import '../payloads/cash_binding_payload.dart';
import '../payloads/cash_movement_evidence.dart';
import 'cash_session_projection.dart';

abstract interface class CashProjectionStore {
  Future<T> atomic<T>(Future<T> Function() action);
  Future<CashSessionProjection?> find(String id);
  Future<CashSessionProjection?> current(String deviceId);
  Future<CashSessionProjection?> latest(String deviceId);
  Future<List<CashMovementEvidence>> movements(String sessionId);
  Future<void> insertSession(SyncEvent event, CajaAbiertaPayload payload);
  Future<void> closeSession(SyncEvent event, CajaCerradaPayload payload);
  Future<void> insertMovement(
    SyncEvent event,
    CashBindingPayload binding,
    CashMovementEvidence evidence,
  );
  Future<void> acknowledge(String eventId, int sequence);
}
