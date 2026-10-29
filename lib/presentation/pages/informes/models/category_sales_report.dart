import '../../../../domain/articulos/articulo_listado.dart';
import '../../../../domain/ventas/confirmed_sale.dart';
import 'category_sale_entry.dart';
import 'category_sales_group.dart';
import 'report_period.dart';
import 'sales_reports_calculator.dart';

/// Informe local con clasificación del catálogo actual e importes del snapshot.
class CategorySalesReport {
  CategorySalesReport({required this.categories});
  final List<CategorySalesGroup> categories;

  static CategorySalesReport calculate(
    ReportPeriod period,
    List<ConfirmedSale> sales,
    List<ArticuloListado> articles,
  ) {
    final catalog = {
      for (final article in articles)
        for (final variant in article.variantesActivas)
          variant.varianteId: article,
    };
    final grouped = <String, List<CategorySaleEntry>>{};
    final labels = <String, String>{};
    void add(CategorySaleEntry entry) {
      final article = catalog[entry.line?.variantId];
      final key = article == null
          ? 'unavailable'
          : article.categoriaId == null
          ? 'uncategorized'
          : 'category:${article.categoriaId}';
      labels[key] = article == null
          ? 'Fuera del catálogo actual'
          : article.categoriaNombre ?? 'Sin categoría';
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    for (final sale in SalesReportsCalculator.salesInPeriod(period, sales)) {
      for (final line in sale.items) {
        add(
          CategorySaleEntry(
            sale: sale,
            line: line,
            amountMinor: BigInt.from(line.totalMinor),
            costMinor: line.standardCostMinor == null
                ? null
                : SalesReportsCalculator.lineCost(
                    line,
                    line.standardCostMinor!,
                  ),
            quantityAtomic: BigInt.from(
              line.quantity ?? line.measuredQuantityAtomic!,
            ),
          ),
        );
      }
    }
    for (final sale in sales) {
      for (final adjustment in SalesReportsCalculator.adjustmentsInPeriod(
        period,
        [sale],
      )) {
        for (final adjusted in adjustment.lines) {
          final matches = sale.items.where((l) => l.id == adjusted.saleItemId);
          add(
            CategorySaleEntry(
              sale: sale,
              line: matches.firstOrNull,
              amountMinor: -BigInt.from(adjusted.amountMinor),
              costMinor: adjusted.recoveredCostMinor == null
                  ? null
                  : -BigInt.from(adjusted.recoveredCostMinor!),
              quantityAtomic: -BigInt.from(adjusted.quantityAtomic),
              adjustmentId: adjustment.operationId,
            ),
          );
        }
      }
    }
    final categories = [
      for (final entry in grouped.entries)
        CategorySalesGroup(
          key: entry.key,
          label: labels[entry.key]!,
          entries: entry.value,
        ),
    ]..sort(byAmount);
    return CategorySalesReport(categories: List.unmodifiable(categories));
  }

  static int byAmount(CategorySalesGroup a, CategorySalesGroup b) {
    final amount = b.totalMinor.compareTo(a.totalMinor);
    return amount != 0 ? amount : a.key.compareTo(b.key);
  }

  /// Separa unidades incompatibles y conserva nombres históricos del ticket.
  static List<CategorySalesGroup> products(
    CategorySalesGroup category, {
    bool byQuantity = false,
  }) {
    final grouped = <String, List<CategorySaleEntry>>{};
    for (final entry in category.entries) {
      final key = '${entry.line?.variantId}:${entry.unit}:${entry.factor}';
      grouped.putIfAbsent(key, () => []).add(entry);
    }
    final result = [
      for (final group in grouped.entries)
        CategorySalesGroup(
          key: group.key,
          label: group.value.first.line == null
              ? 'Línea no disponible'
              : [
                  group.value.first.line!.productName,
                  group.value.first.line!.variantName,
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          entries: group.value,
        ),
    ];
    result.sort((a, b) {
      if (!byQuantity) return byAmount(a, b);
      final unit = a.unit.compareTo(b.unit);
      if (unit != 0) return unit;
      final quantity = (b.quantityAtomic * BigInt.from(a.factor)).compareTo(
        a.quantityAtomic * BigInt.from(b.factor),
      );
      return quantity != 0 ? quantity : a.key.compareTo(b.key);
    });
    return result;
  }
}
