import 'supplier_order_json.dart';
import 'supplier_receipt_line.dart';

/// Contrato v1 compartido por comandos, recepción y recuperación.
class SupplierReceiptConfirmedPayload {
  static const aggregateType = 'supplier_order';
  static const eventType = 'supplier_receipt_confirmed';
  SupplierReceiptConfirmedPayload._(
    this.contractVersion,
    this.orderId,
    this.baseEventId,
    this.occurredAtMs,
    this.receiptId,
    this.items,
    this.totalMinor,
  );
  final int contractVersion;
  final String orderId;
  final String baseEventId;
  final int occurredAtMs;
  final String receiptId;
  final List<SupplierReceiptLine> items;
  final int totalMinor;
  factory SupplierReceiptConfirmedPayload.fromJson(Object? value) {
    final j = orderRecord(value);
    orderPayloadSize(j);
    final p = SupplierReceiptConfirmedPayload._(
      orderInt(j['contract_version'], 1),
      orderUuid(j['order_id']),
      orderUuid(j['base_event_id']),
      orderInt(j['occurred_at_ms'], 1),
      orderUuid(j['receipt_id']),
      orderLines(
        j['items'],
        SupplierReceiptLine.fromJson,
        (l) => l.orderItemId,
      ),
      orderInt(j['total_minor']),
    );
    if (p.contractVersion != 1) throw const FormatException('Versión inválida');
    if (p.totalMinor != orderTotal(p.items.map((l) => l.totalMinor)) ||
        p.items.map((l) => l.movementId).toSet().length != p.items.length) {
      throw const FormatException('Recepción incoherente');
    }
    return p;
  }
  Map<String, Object?> toJson() => {
    'contract_version': contractVersion,
    'order_id': orderId,
    'base_event_id': baseEventId,
    'occurred_at_ms': occurredAtMs,
    'receipt_id': receiptId,
    'items': items.map((l) => l.toJson()).toList(),
    'total_minor': totalMinor,
  };
}
