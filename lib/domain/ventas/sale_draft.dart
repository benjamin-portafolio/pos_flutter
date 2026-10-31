import 'sale_draft_item.dart';

/// Una venta en preparación del usuario y dispositivo, con importes persistidos.
class SaleDraft {
  SaleDraft({
    required this.id,
    this.lastEventId,
    this.version = 0,
    this.pricingMode = 'normal',
    required this.totalMinor,
    required List<SaleDraftItem> items,
  }) : items = List.unmodifiable(items);

  final int version;
  final String pricingMode;
  final String id;
  final String? lastEventId;
  final int totalMinor;
  final List<SaleDraftItem> items;

  int get articleCount => items.map((item) => item.variantId).toSet().length;
}
