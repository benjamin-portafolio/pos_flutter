import '../payloads/supplier_order_line.dart';
import '../payloads/supplier_receipt_confirmed_payload.dart';
import '../payloads/supplier_order_closed_payload.dart';
import '../../../domain/proveedores/replenishment_candidate.dart';
import '../models/sync_event.dart';
import 'supplier_order_projection.dart';

abstract interface class SupplierOrderProjectionStore {
  Future<SupplierOrderProjection?> find(String id);
  Future<void> validateLineIdentities(
    SyncEvent event,
    List<SupplierOrderLine> lines,
  );
  Future<bool> receiptApplied(SyncEvent event);
  Future<void> receive(
    SyncEvent event,
    SupplierReceiptConfirmedPayload payload,
  );
  Future<void> closeRemainder(
    SyncEvent event,
    SupplierOrderClosedPayload payload,
  );
  Future<void> acknowledgeEffects(SyncEvent event);
  Future<void> write(SupplierOrderProjection order);
  Future<List<ReplenishmentCandidate>> candidates();
  Future<bool> hasReceipts(String id);
  Future<void> acknowledge(String id, int sequence);
  Future<void> restore(SyncEvent event);
  Future<SyncEvent?> eventById(String id);
}
