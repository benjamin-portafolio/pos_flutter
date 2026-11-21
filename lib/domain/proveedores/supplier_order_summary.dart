class SupplierOrderSummary {
  const SupplierOrderSummary({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.status,
    required this.occurredAtMs,
    required this.totalMinor,
    required this.deliveryStatus,
    required this.issue,
    required this.overlaps,
  });
  final String id, supplierId, supplierName, status, deliveryStatus;
  final String? issue;
  final int occurredAtMs;
  final int? totalMinor;
  final bool overlaps;
}
