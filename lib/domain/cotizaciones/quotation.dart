import 'quotation_item.dart';
import 'quotation_status.dart';

/// Selección durable de productos y cantidades, independiente de la venta.
class Quotation {
  Quotation({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.issuedAtLocal,
    required this.sourceSaleId,
    required this.sourceDraftEventId,
    required this.currentSaleId,
    required this.status,
    required this.lastEventId,
    required List<QuotationItem> items,
  }) : items = List.unmodifiable(items);

  final String id, userId, deviceId, sourceSaleId, sourceDraftEventId;
  final String? currentSaleId, lastEventId;
  final DateTime issuedAtLocal;
  final QuotationStatus status;
  final List<QuotationItem> items;
}
