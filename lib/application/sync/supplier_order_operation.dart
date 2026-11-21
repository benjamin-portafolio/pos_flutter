import 'models/sync_event.dart';
import 'payloads/supplier_receipt_confirmed_payload.dart';
import 'payloads/supplier_order_closed_payload.dart';
import 'payloads/supplier_order_draft_saved_payload.dart';
import 'payloads/supplier_order_confirmed_payload.dart';
import 'payloads/supplier_order_cancelled_payload.dart';

/// Decodificación tipada de operaciones del agregado pedido y sus recepciones.
class SupplierOrderOperation {
  SupplierOrderOperation._(
    this.orderId,
    this.baseEventId,
    this.status,
    this.document,
  );
  static const eventTypes = {
    SupplierOrderDraftSavedPayload.eventType,
    SupplierOrderConfirmedPayload.eventType,
    SupplierOrderCancelledPayload.eventType,
    SupplierReceiptConfirmedPayload.eventType,
    SupplierOrderClosedPayload.eventType,
  };
  final String orderId, status;
  final String? baseEventId;
  final SupplierOrderDraftSavedPayload? document;
  factory SupplierOrderOperation.decode(SyncEvent event) {
    if (event.aggregateType != SupplierOrderDraftSavedPayload.aggregateType ||
        !eventTypes.contains(event.eventType)) {
      throw const FormatException('Operación de pedido inválida.');
    }
    late SupplierOrderOperation result;
    switch (event.eventType) {
      case SupplierOrderDraftSavedPayload.eventType:
        final p = SupplierOrderDraftSavedPayload.fromJson(event.payload);
        result = SupplierOrderOperation._(p.orderId, p.baseEventId, 'draft', p);
      case SupplierOrderConfirmedPayload.eventType:
        final p = SupplierOrderConfirmedPayload.fromJson(event.payload);
        result = SupplierOrderOperation._(
          p.orderId,
          p.baseEventId,
          'confirmed',
          SupplierOrderDraftSavedPayload.fromJson(p.toJson()),
        );
      case SupplierReceiptConfirmedPayload.eventType:
        final p = SupplierReceiptConfirmedPayload.fromJson(event.payload);
        result = SupplierOrderOperation._(
          p.orderId,
          p.baseEventId,
          'receipt',
          null,
        );
      case SupplierOrderClosedPayload.eventType:
        final p = SupplierOrderClosedPayload.fromJson(event.payload);
        result = SupplierOrderOperation._(
          p.orderId,
          p.baseEventId,
          'closed',
          null,
        );
      default:
        final p = SupplierOrderCancelledPayload.fromJson(event.payload);
        result = SupplierOrderOperation._(
          p.orderId,
          p.baseEventId,
          'cancelled',
          null,
        );
    }
    if (event.aggregateId != result.orderId ||
        event.baseVersion == null ||
        event.baseVersion! < 1 ||
        (result.baseEventId == null &&
            (event.baseVersion != 1 || event.baseServerSequence != null))) {
      throw const FormatException('Identidad o base de pedido inválida.');
    }
    return result;
  }
}
