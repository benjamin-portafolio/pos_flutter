import '../../sync/payloads/supplier_order_draft_saved_payload.dart';

/// IDs generados antes del intento; bases e intención conservadas al reintentar.
class SaveSupplierOrderCommand {
  const SaveSupplierOrderCommand({
    required this.eventId,
    required this.document,
    required this.catalogBasis,
    this.confirm = false,
  });
  final String eventId;
  final SupplierOrderDraftSavedPayload document;
  final Map<String, String> catalogBasis;
  final bool confirm;
}
