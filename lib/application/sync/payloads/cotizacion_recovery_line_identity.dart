import 'quotation_json.dart';
import 'inventory_movement_payload.dart';

/// Mapa de identidades, sin snapshots de venta ni datos monetarios.
class CotizacionRecoveryLineIdentity {
  CotizacionRecoveryLineIdentity({
    required String quotationItemId,
    required String saleItemId,
    required String draftEventId,
    required this.sortOrder,
  }) : quotationItemId = quotationItemId.trim(),
       saleItemId = saleItemId.trim(),
       draftEventId = draftEventId.trim() {
    InventoryMovementPayload.requiredUuidV4(this.saleItemId, 'sale_item_id');
    InventoryMovementPayload.requiredUuidV4(
      this.draftEventId,
      'draft_event_id',
    );
    if (this.quotationItemId.isEmpty ||
        this.quotationItemId == this.saleItemId ||
        sortOrder < 0 ||
        sortOrder > QuotationJson.maxInteger) {
      throw const FormatException('Identidad de línea inválida.');
    }
  }
  final String quotationItemId, saleItemId, draftEventId;
  final int sortOrder;
  Map<String, Object?> toJson() => {
    'quotation_item_id': quotationItemId,
    'sale_item_id': saleItemId,
    'draft_event_id': draftEventId,
    'sort_order': sortOrder,
  };
  factory CotizacionRecoveryLineIdentity.fromJson(Map<String, Object?> j) {
    QuotationJson.keys(j, {
      'quotation_item_id',
      'sale_item_id',
      'draft_event_id',
      'sort_order',
    });
    return CotizacionRecoveryLineIdentity(
      quotationItemId: QuotationJson.text(j, 'quotation_item_id')!,
      saleItemId: QuotationJson.text(j, 'sale_item_id')!,
      draftEventId: QuotationJson.text(j, 'draft_event_id')!,
      sortOrder: QuotationJson.number(j, 'sort_order')!,
    );
  }
}
