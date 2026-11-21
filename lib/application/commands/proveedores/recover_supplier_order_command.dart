class RecoverSupplierOrderCommand {
  const RecoverSupplierOrderCommand({
    required this.eventId,
    required this.orderId,
    required this.sourceEventId,
    required this.itemIds,
    required this.occurredAtMs,
  });
  final String eventId, orderId, sourceEventId;
  final Map<String, String> itemIds;
  final int occurredAtMs;
}
