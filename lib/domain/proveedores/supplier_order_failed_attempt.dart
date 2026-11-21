class SupplierOrderFailedAttempt {
  const SupplierOrderFailedAttempt({
    required this.eventId,
    required this.orderId,
    required this.supplierName,
    required this.reason,
    required this.status,
    this.canRecoverDraft = true,
  });
  final bool canRecoverDraft;
  final String eventId, orderId, supplierName, reason, status;
}
