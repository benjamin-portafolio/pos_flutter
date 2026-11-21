import 'supplier_order_json.dart';
import 'supplier_closed_line.dart';

/// Contrato v1 compartido por comandos, recepción y recuperación.
class SupplierOrderClosedPayload {
  static const aggregateType = 'supplier_order';
  static const eventType = 'supplier_order_closed';
  SupplierOrderClosedPayload._(
    this.contractVersion,
    this.orderId,
    this.baseEventId,
    this.occurredAtMs,
    this.items,
  );
  final int contractVersion;
  final String orderId;
  final String baseEventId;
  final int occurredAtMs;
  final List<SupplierClosedLine> items;
  factory SupplierOrderClosedPayload.fromJson(Object? value) {
    final j = orderRecord(value);
    orderPayloadSize(j);
    final p = SupplierOrderClosedPayload._(
      orderInt(j['contract_version'], 1),
      orderUuid(j['order_id']),
      orderUuid(j['base_event_id']),
      orderInt(j['occurred_at_ms'], 1),
      orderLines(j['items'], SupplierClosedLine.fromJson, (l) => l.orderItemId),
    );
    if (p.contractVersion != 1) throw const FormatException('Versión inválida');
    return p;
  }
  Map<String, Object?> toJson() => {
    'contract_version': contractVersion,
    'order_id': orderId,
    'base_event_id': baseEventId,
    'occurred_at_ms': occurredAtMs,
    'items': items.map((l) => l.toJson()).toList(),
  };
}
