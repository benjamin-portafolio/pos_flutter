import 'supplier_order_json.dart';
import 'supplier_order_line.dart';

/// Contrato documental v1; las operaciones de pedidos se aplican en S3.
class SupplierOrderConfirmedPayload {
  static const aggregateType = 'supplier_order';
  static const eventType = 'supplier_order_confirmed';
  SupplierOrderConfirmedPayload._(
    this.contractVersion,
    this.orderId,
    this.baseEventId,
    this.supplierId,
    this.supplierNameSnapshot,
    this.supplierPhoneSnapshot,
    this.currency,
    this.occurredAtMs,
    this.notes,
    this.items,
    this.totalMinor,
  );
  final int contractVersion;
  final String orderId;
  final String? baseEventId;
  final String supplierId;
  final String supplierNameSnapshot;
  final String? supplierPhoneSnapshot;
  final String currency;
  final int occurredAtMs;
  final String? notes;
  final List<SupplierOrderLine> items;
  final int? totalMinor;
  factory SupplierOrderConfirmedPayload.fromJson(Object? value) {
    final j = orderRecord(value);
    orderPayloadSize(j);
    final p = SupplierOrderConfirmedPayload._(
      orderInt(j['contract_version'], 1),
      orderUuid(j['order_id']),
      j['base_event_id'] == null ? null : orderUuid(j['base_event_id']),
      orderUuid(j['supplier_id']),
      orderText(j['supplier_name_snapshot'], 160),
      j['supplier_phone_snapshot'] == null
          ? null
          : orderText(j['supplier_phone_snapshot'], 80),
      orderText(j['currency'], 3),
      orderInt(j['occurred_at_ms'], 1),
      j['notes'] == null ? null : orderText(j['notes'], 1000),
      orderLines(j['items'], SupplierOrderLine.fromJson, (l) => l.id),
      j['total_minor'] == null ? null : orderInt(j['total_minor']),
    );
    if (p.contractVersion != 1 ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(p.currency) ||
        p.totalMinor != orderTotal(p.items.map((l) => l.totalMinor)) ||
        p.items.map((l) => l.variantId).toSet().length != p.items.length) {
      throw const FormatException('Documento incoherente');
    }
    if (p.baseEventId == null) throw const FormatException('Base requerida');
    return p;
  }
  Map<String, Object?> toJson() => {
    'contract_version': contractVersion,
    'order_id': orderId,
    'base_event_id': baseEventId,
    'supplier_id': supplierId,
    'supplier_name_snapshot': supplierNameSnapshot,
    'supplier_phone_snapshot': supplierPhoneSnapshot,
    'currency': currency,
    'occurred_at_ms': occurredAtMs,
    'notes': notes,
    'items': items.map((l) => l.toJson()).toList(),
    'total_minor': totalMinor,
  };
}
