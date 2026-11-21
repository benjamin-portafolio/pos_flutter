import 'sync_projection.dart';
import '../payloads/supplier_order_draft_saved_payload.dart';

class SupplierOrderProjection extends SyncProjection {
  SupplierOrderProjection({
    required this.document,
    required this.status,
    required super.version,
    required super.createdEventId,
    required super.lastEventId,
    required super.lastServerSequence,
  }) : super(id: document.orderId, active: true);
  final SupplierOrderDraftSavedPayload document;
  final String status;
}
