import 'supplier_order_json.dart';

/// Contrato documental v1; las operaciones de pedidos se aplican en S3.
class SupplierOrderCancelledPayload {
  static const aggregateType = 'supplier_order';
  static const eventType = 'supplier_order_cancelled';
  SupplierOrderCancelledPayload._(
    this.contractVersion,
    this.orderId,
    this.baseEventId,
    this.occurredAtMs,
  );
  final int contractVersion;
  final String orderId;
  final String baseEventId;
  final int occurredAtMs;
  factory SupplierOrderCancelledPayload.fromJson(Object? value) {
    final j = orderRecord(value);
    orderPayloadSize(j);
    final p = SupplierOrderCancelledPayload._(
      orderInt(j['contract_version'], 1),
      orderUuid(j['order_id']),
      orderUuid(j['base_event_id']),
      orderInt(j['occurred_at_ms'], 1),
    );
    if (p.contractVersion != 1) throw const FormatException('Versión inválida');
    return p;
  }
  Map<String, Object?> toJson() => {
    'contract_version': contractVersion,
    'order_id': orderId,
    'base_event_id': baseEventId,
    'occurred_at_ms': occurredAtMs,
  };
}
