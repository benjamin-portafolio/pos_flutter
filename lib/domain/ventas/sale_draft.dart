import 'sale_draft_item.dart';

/// Borrador actual del usuario y dispositivo, con importes persistidos.
class SaleDraft {
  SaleDraft({
    required this.id,
    this.lastEventId,
    required this.totalMinor,
    required List<SaleDraftItem> items,
  }) : items = List.unmodifiable(items);

  final String id;
  final String? lastEventId;
  final int totalMinor;
  final List<SaleDraftItem> items;

  int get articleCount => items.map((item) => item.variantId).toSet().length;
}
