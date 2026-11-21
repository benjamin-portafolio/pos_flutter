class CancelSupplierOrderCommand {
  const CancelSupplierOrderCommand({
    required this.eventId,
    required this.orderId,
    required this.baseEventId,
    required this.occurredAtMs,
  });
  final String eventId, orderId, baseEventId;
  final int occurredAtMs;
}
