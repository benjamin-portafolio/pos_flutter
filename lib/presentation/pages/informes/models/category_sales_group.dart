import 'beneficio_bruto_report.dart';
import 'category_sale_entry.dart';

/// Grupo de categorías o variantes, con sus aportes y costos históricos.
class CategorySalesGroup {
  CategorySalesGroup({
    required this.key,
    required this.label,
    required Iterable<CategorySaleEntry> entries,
  }) : entries = List.unmodifiable(entries);

  final String key;
  final String label;
  final List<CategorySaleEntry> entries;

  BigInt get totalMinor =>
      entries.fold(BigInt.zero, (n, e) => n + e.amountMinor);
  int get saleCount => entries
      .where((e) => e.adjustmentId == null)
      .map((e) => e.sale.id)
      .toSet()
      .length;
  BigInt get quantityAtomic =>
      entries.fold(BigInt.zero, (n, e) => n + e.quantityAtomic);
  String get unit => entries.first.unit;
  int get factor => entries.first.factor;

  BeneficioBrutoReport get gross {
    final known = entries.where((e) => e.costMinor != null).toList();
    final unknown = entries.where((e) => e.costMinor == null).toList();
    return BeneficioBrutoReport(
      estado: unknown.isEmpty
          ? BeneficioBrutoEstado.total
          : known.isEmpty
          ? BeneficioBrutoEstado.noDisponible
          : BeneficioBrutoEstado.parcial,
      profitMinor: known.fold(
        BigInt.zero,
        (n, e) => n + e.amountMinor - e.costMinor!,
      ),
      ventasCount: saleCount,
      lineasConCosto: known.length,
      lineasSinCosto: unknown.length,
      vendidoSinCostoMinor: unknown.fold(
        BigInt.zero,
        (n, e) => n + e.amountMinor,
      ),
    );
  }
}
