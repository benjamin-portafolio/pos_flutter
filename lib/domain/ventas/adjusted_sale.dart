import 'confirmed_sale.dart';
import 'sale_adjustment_document.dart';
import 'sale_adjustment_status.dart';

/// Venta original intacta junto a su historia comercial y entrega separadas.
class AdjustedSale {
  AdjustedSale({
    required this.original,
    required this.status,
    required List<SaleAdjustmentDocument> adjustments,
  }) : adjustments = List.unmodifiable(adjustments);
  final ConfirmedSale original;
  final SaleAdjustmentStatus status;
  final List<SaleAdjustmentDocument> adjustments;
  int get revision => adjustments.isEmpty
      ? 0
      : adjustments.map((a) => a.localRevision).reduce((a, b) => a > b ? a : b);
  int get officialRevision => adjustments.isEmpty
      ? 0
      : adjustments
            .map((a) => a.officialRevision)
            .reduce((a, b) => a > b ? a : b);
  bool get hasIncident => adjustments.any((a) => a.incidentId != null);
  SaleAdjustmentStatus get officialStatus => adjustments.isEmpty
      ? SaleAdjustmentStatus.current
      : adjustments.last.officialStatus;

  /// Remanente comercial en las unidades atómicas históricas de cada línea.
  Map<String, int> get remainingQuantities => Map.unmodifiable({
    for (final item in original.items)
      item.id: status == SaleAdjustmentStatus.voided
          ? 0
          : (item.quantity ?? item.measuredQuantityAtomic!) -
                adjustments
                    .where(
                      (a) =>
                          !['conflict', 'rejected'].contains(a.deliveryStatus),
                    )
                    .expand((a) => a.lines)
                    .where((l) => l.saleItemId == item.id)
                    .fold(0, (n, l) => n + l.quantityAtomic),
  });
}
