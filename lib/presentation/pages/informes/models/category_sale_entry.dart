import '../../../../domain/ventas/confirmed_sale.dart';
import '../../../../domain/ventas/sale_draft_item.dart';

/// Aporte firmado de una línea o ajuste; conserva el ticket que lo explica.
class CategorySaleEntry {
  const CategorySaleEntry({
    required this.sale,
    required this.line,
    required this.amountMinor,
    required this.costMinor,
    required this.quantityAtomic,
    this.adjustmentId,
  });

  final ConfirmedSale sale;
  final SaleDraftItem? line;
  final BigInt amountMinor;
  final BigInt? costMinor;
  final BigInt quantityAtomic;
  final String? adjustmentId;

  String get unit => line?.quantity != null ? 'pzas' : line?.unitSymbol ?? '—';
  int get factor => line?.quantity != null ? 1 : line?.unitAtomicFactor ?? 1;
}
