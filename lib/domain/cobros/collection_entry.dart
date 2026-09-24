/// Dinero recibido una sola vez, independiente de aplicaciones y entrega remota.
class CollectionEntry {
  const CollectionEntry({
    required this.id,
    required this.eventId,
    required this.amountMinor,
    required this.method,
    required this.date,
    required this.origin,
    required this.userId,
    required this.deviceId,
    required this.deliveryStatus,
    this.reference,
    this.saleId,
    this.clienteId,
    this.clienteNombre,
    this.reason,
  });
  final String id, eventId, method, origin, userId, deviceId, deliveryStatus;
  final String? reference, saleId, clienteId, clienteNombre, reason;
  final int amountMinor;
  final DateTime date;
}
