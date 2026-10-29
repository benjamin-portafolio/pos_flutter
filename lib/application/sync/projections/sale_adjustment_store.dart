import '../models/sale_adjustment_delivery_state.dart';
import '../models/sync_event.dart';
import '../payloads/sale_adjustment_payload.dart';

/// Lectura autoritativa y proyección bajo la transacción del event store.
abstract interface class SaleAdjustmentStore {
  Future<SaleAdjustmentDeliveryState> readDeliveryState();
  Future<void> prepareOfficial(SyncEvent event);
  Future<void> acknowledge(String eventId, int sequence);
  Future<bool> hasIncident(String saleId);
  Future<T> atomic<T>(Future<T> Function() action);
  Future<SyncEvent?> confirmation(String saleId);
  Future<List<SyncEvent>> history(String saleId);
  Future<SyncEvent?> existing(String operationId, String eventId);
  Future<void> reserveIntention(SyncEvent event);
  Future<List<SyncEvent>> recoverableIntentions(String saleId);
  Future<SyncEvent?> recoverIntention(String operationId);
  Future<void> applyEffects(SyncEvent event, SaleAdjustmentPayload payload);
  Future<void> persistDocument(SyncEvent event, SaleAdjustmentPayload payload);
}
