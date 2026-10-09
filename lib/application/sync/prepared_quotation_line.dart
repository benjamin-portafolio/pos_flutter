import 'local_event_store.dart';
import 'payloads/sale_item_snapshot.dart';

/// Condiciones vigentes preparadas en memoria para un evento sale_draft.
class PreparedQuotationLine {
  const PreparedQuotationLine({
    required this.quotationItemId,
    required this.productId,
    required this.unitId,
    required this.sortOrder,
    required this.snapshot,
  });
  final String quotationItemId, productId;
  final String? unitId;
  final int sortOrder;
  final SaleItemSnapshot snapshot;
  List<LocalEventRef> refs(String saleId, String saleItemId) {
    if ([
          saleId,
          saleItemId,
          productId,
          snapshot.variantId,
        ].any((id) => id.trim().isEmpty) ||
        saleId == saleItemId ||
        (snapshot.saleMode == 'measured'
            ? unitId == null || unitId!.trim().isEmpty
            : unitId != null)) {
      throw const FormatException('Referencias de borrador inválidas.');
    }
    return [
      LocalEventRef.affects(refType: 'sale', refId: saleId),
      LocalEventRef.affects(refType: 'sale_item', refId: saleItemId),
      LocalEventRef.uses(refType: 'product', refId: productId),
      LocalEventRef.uses(refType: 'product_variant', refId: snapshot.variantId),
      if (unitId != null) LocalEventRef.uses(refType: 'unit', refId: unitId!),
    ];
  }
}
