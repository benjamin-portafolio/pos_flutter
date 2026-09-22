/// Movimiento de cuenta. Importe positivo: isPayment define abono o cargo.
class AccountEntry {
  const AccountEntry({
    required this.id,
    required this.eventId,
    required this.amountMinor,
    required this.occurredAtMs,
    required this.isPayment,
    required this.deliveryStatus,
    this.saleId,
    this.method,
    this.reference,
    this.reason,
    this.userId,
    this.deviceId,
  });
  final String id, eventId, deliveryStatus;
  final int amountMinor, occurredAtMs;
  final bool isPayment;
  final String? saleId, method, reference, reason, userId, deviceId;
  DateTime get date =>
      DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true).toLocal();
  bool get needsAttention =>
      deliveryStatus == 'conflict' || deliveryStatus == 'rejected';
  static int compare(AccountEntry a, AccountEntry b) {
    final date = a.occurredAtMs.compareTo(b.occurredAtMs);
    return date == 0 ? a.id.compareTo(b.id) : date;
  }
}
