import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/ventas/sale_adjustment_document.dart';
import 'package:pos_flutter/domain/ventas/sale_adjustment_status.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import 'package:pos_flutter/presentation/pages/informes/models/sales_reports_calculator.dart';
import 'package:pos_flutter/presentation/pages/informes/models/sales_time_bucket.dart';
import 'package:pos_flutter/presentation/pages/informes/models/sales_time_grouping.dart';

ConfirmedSale sale(
  DateTime date,
  int total, {
  List<SaleAdjustmentDocument> adjustments = const [],
}) => ConfirmedSale(
  id: '$date',
  createdAt: date,
  totalMinor: total,
  receivedMinor: total + 100,
  changeMinor: 100,
  currency: 'MXN',
  deliveryStatus: 'not_required',
  reason: null,
  items: [],
  adjustments: adjustments,
);

SaleAdjustmentDocument adjustment(String status) => SaleAdjustmentDocument(
  operationId: status,
  eventId: status,
  saleId: 'old',
  businessDate: '2026-10-29',
  reason: 'Devolución',
  userId: 'user',
  deviceId: 'device',
  occurredAt: DateTime(2026, 10, 30, 9).toUtc(),
  amountMinor: 350,
  method: 'cash',
  settlementAction: 'refund',
  deliveryStatus: status,
  officialStatus: SaleAdjustmentStatus.current,
  localStatus: SaleAdjustmentStatus.current,
  officialRevision: 0,
  localRevision: 0,
  lines: [],
  physicalEffectIds: [],
);

void main() {
  test(
    'agrupa horas locales repetidas y ordena por monto con desempate estable',
    () {
      final buckets =
          SalesTimeBucket.calculate(ReportPeriod.month(DateTime(2026, 10)), [
            sale(DateTime(2026, 10, 29, 9).toUtc(), 150),
            sale(DateTime(2026, 10, 28, 9, 59), 250),
            sale(DateTime(2026, 10, 29, 11), 400),
          ], SalesTimeGrouping.hour);
      expect(buckets.map((b) => b.key), [9, 11]);
      expect(buckets.first.totalMinor, BigInt.from(400));
      expect(buckets.first.sales.length, 2);
      expect(buckets.first.label, '09:00 – 10:00');
    },
  );

  test('día de semana reúne fechas distintas; meses conservan el año', () {
    final sales = [
      sale(DateTime(2025, 10, 30), 100),
      sale(DateTime(2026, 10, 29), 200),
    ];
    final period = ReportPeriod.range(DateTime(2025), DateTime(2026, 12, 31));
    final weekdays = SalesTimeBucket.calculate(
      period,
      sales,
      SalesTimeGrouping.weekday,
    );
    expect(weekdays.single.label, 'Jueves');
    expect(weekdays.single.totalMinor, BigInt.from(300));
    final months = SalesTimeBucket.calculate(
      period,
      sales,
      SalesTimeGrouping.month,
    );
    expect(months.map((b) => b.label), ['octubre 2026', 'octubre 2025']);
  });

  test(
    'límites de período y ajustes de ventas anteriores concilian con total',
    () {
      final period = ReportPeriod.day(DateTime(2026, 10, 29));
      final sales = [
        sale(
          DateTime(2026, 10, 28),
          1000,
          adjustments: [
            adjustment('not_required'),
            adjustment('rejected'),
            adjustment('conflict'),
          ],
        ),
        sale(DateTime(2026, 10, 29), 100),
        sale(DateTime(2026, 10, 29, 23, 59, 59, 999), 200),
        sale(DateTime(2026, 10, 30), 9999),
      ];
      for (final grouping in SalesTimeGrouping.values) {
        final buckets = SalesTimeBucket.calculate(period, sales, grouping);
        expect(
          buckets.fold(BigInt.zero, (sum, b) => sum + b.totalMinor),
          SalesReportsCalculator.ventasTotales(period, sales),
        );
        expect(buckets.expand((b) => b.adjustments).length, 1);
        expect(buckets.expand((b) => b.sales).length, 2);
      }
      final hours = SalesTimeBucket.calculate(
        period,
        sales,
        SalesTimeGrouping.hour,
      );
      expect(hours.last.key, 9);
      expect(hours.last.totalMinor, BigInt.from(-350));
      expect(
        SalesTimeBucket.calculate(
          period,
          sales,
          SalesTimeGrouping.weekday,
        ).single.label,
        'Jueves',
      );
    },
  );

  test('sin operaciones no crea grupos y conserva precisión de enteros', () {
    final period = ReportPeriod.day(DateTime(2026, 10, 29));
    expect(
      SalesTimeBucket.calculate(period, [], SalesTimeGrouping.hour),
      isEmpty,
    );
    final buckets = SalesTimeBucket.calculate(period, [
      sale(period.start, 9007199254740991),
      sale(period.start, 9007199254740991),
    ], SalesTimeGrouping.hour);
    expect(buckets.single.totalMinor, BigInt.parse('18014398509481982'));
  });
}
