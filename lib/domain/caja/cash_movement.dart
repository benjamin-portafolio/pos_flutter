class CashMovement {
  const CashMovement({
    required this.id,
    required this.eventId,
    required this.direction,
    required this.amountMinor,
    required this.sourceType,
    required this.sourceId,
    required this.deliveryStatus,
    this.rejectionReason,
  });
  final String id, eventId, direction, sourceType, sourceId, deliveryStatus;
  final int amountMinor;
  final String? rejectionReason;
}
