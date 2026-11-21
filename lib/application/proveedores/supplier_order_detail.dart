import '../sync/projections/supplier_order_projection.dart';
import '../sync/payloads/supplier_receipt_confirmed_payload.dart';
import '../sync/payloads/supplier_order_line.dart';

/// Immutable read snapshot, read in one transaction by the adapter.
class SupplierOrderDetail {
  SupplierOrderDetail({
    required this.order,
    required this.receipts,
    required this.failedReceipts,
    required this.received,
    required this.closed,
    required this.balances,
    required this.deliveryStatus,
    required this.receiptStatuses,
    required this.failures,
    required this.catalogBasis,
    required this.reviewBasis,
  });
  final SupplierOrderProjection order;
  final List<SupplierReceiptConfirmedPayload> receipts, failedReceipts;
  final Map<String, int> received, closed, balances;
  final Map<String, String> catalogBasis;
  final String deliveryStatus, reviewBasis;
  final Map<String, String> receiptStatuses;
  final List<String> failures;
  int pending(SupplierOrderLine l) =>
      (l.quantityAtomic - (received[l.id] ?? 0) - (closed[l.id] ?? 0)).clamp(
        0,
        9007199254740991,
      );
  int get receivedTotal => receipts.fold(0, (v, r) => v + r.totalMinor);
}
