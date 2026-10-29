import '../../../../domain/ventas/confirmed_sale.dart';
import '../../../../domain/ventas/sale_adjustment_document.dart';
import 'report_period.dart';
import 'sales_reports_calculator.dart';
import 'sales_time_grouping.dart';

/// Ventas y ajustes que explican exactamente el importe neto de un grupo.
class SalesTimeBucket {
  SalesTimeBucket({
    required this.key,
    required this.label,
    required Iterable<ConfirmedSale> sales,
    required Iterable<SaleAdjustmentDocument> adjustments,
  }) : sales = List.unmodifiable(sales),
       adjustments = List.unmodifiable(adjustments);

  final int key;
  final String label;
  final List<ConfirmedSale> sales;
  final List<SaleAdjustmentDocument> adjustments;

  BigInt get totalMinor =>
      sales.fold(
        BigInt.zero,
        (sum, sale) => sum + BigInt.from(sale.totalMinor),
      ) -
      adjustments.fold(
        BigInt.zero,
        (sum, adjustment) => sum + BigInt.from(adjustment.amountMinor),
      );

  /// Conserva las mismas fechas y exclusiones que Ventas totales. Los ajustes
  /// usan su fecha de negocio; para la hora se usa la de ocurrencia local.
  static List<SalesTimeBucket> calculate(
    ReportPeriod period,
    Iterable<ConfirmedSale> sales,
    SalesTimeGrouping grouping,
  ) {
    final inPeriod = SalesReportsCalculator.salesInPeriod(period, sales);
    final adjustments = SalesReportsCalculator.adjustmentsInPeriod(
      period,
      sales,
    );
    final groupedSales = <int, List<ConfirmedSale>>{};
    final groupedAdjustments = <int, List<SaleAdjustmentDocument>>{};
    for (final sale in inPeriod) {
      groupedSales
          .putIfAbsent(grouping.key(sale.createdAt), () => [])
          .add(sale);
    }
    for (final adjustment in adjustments) {
      final date = grouping == SalesTimeGrouping.hour
          ? adjustment.occurredAt
          : DateTime.parse(adjustment.businessDate);
      groupedAdjustments
          .putIfAbsent(grouping.key(date), () => [])
          .add(adjustment);
    }
    final result = [
      for (final key in {...groupedSales.keys, ...groupedAdjustments.keys})
        SalesTimeBucket(
          key: key,
          label: grouping.bucketLabel(key),
          sales: (groupedSales[key] ?? [])
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          adjustments: (groupedAdjustments[key] ?? [])
            ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt)),
        ),
    ];
    result.sort((a, b) {
      final amount = b.totalMinor.compareTo(a.totalMinor);
      return amount == 0 ? a.key.compareTo(b.key) : amount;
    });
    return result;
  }
}
