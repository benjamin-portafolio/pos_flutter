import '../../sync/payloads/supplier_order_closed_payload.dart';

class CloseSupplierOrderCommand {
  const CloseSupplierOrderCommand({
    required this.eventId,
    required this.payload,
  });
  final String eventId;
  final SupplierOrderClosedPayload payload;
}
