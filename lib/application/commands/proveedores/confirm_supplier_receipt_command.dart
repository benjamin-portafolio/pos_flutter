import 'supplier_receipt_input_line.dart';
import '../../sync/payloads/supplier_order_json.dart';
import '../../sync/payloads/supplier_receipt_confirmed_payload.dart';

/// Caller reserves event/receipt/movement identities before the first attempt.
class ConfirmSupplierReceiptCommand {
  const ConfirmSupplierReceiptCommand({
    required this.eventId,
    required this.payload,
    this.catalogBasis,
  });
  factory ConfirmSupplierReceiptCommand.capture({
    required String eventId,
    required String orderId,
    required String baseEventId,
    required String receiptId,
    required int occurredAtMs,
    required List<SupplierReceiptInputLine> items,
    Map<String, String>? catalogBasis,
  }) {
    if (items.isEmpty ||
        items.length > 50 ||
        items.map((i) => i.orderItemId).toSet().length != items.length ||
        items.map((i) => i.movementId).toSet().length != items.length) {
      throw const FormatException('Partidas duplicadas o fuera de límite.');
    }
    final positive = items
        .map((i) => i.validatedJson())
        .where((i) => (i['quantity_atomic'] as int) > 0)
        .toList();
    return ConfirmSupplierReceiptCommand(
      eventId: eventId,
      catalogBasis: catalogBasis,
      payload: SupplierReceiptConfirmedPayload.fromJson({
        'contract_version': 1,
        'order_id': orderId,
        'base_event_id': baseEventId,
        'receipt_id': receiptId,
        'occurred_at_ms': occurredAtMs,
        'items': positive,
        'total_minor': orderTotal(positive.map((i) => i['total_minor'] as int)),
      }),
    );
  }
  final String eventId;
  final Map<String, String>? catalogBasis;
  final SupplierReceiptConfirmedPayload payload;
}
