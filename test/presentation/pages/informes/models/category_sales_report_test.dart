import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/informes/models/category_sales_report.dart';
import 'package:pos_flutter/presentation/pages/informes/models/beneficio_bruto_report.dart';
import 'package:pos_flutter/presentation/pages/informes/models/sales_reports_calculator.dart';
import '../../../../support/category_sales_fixtures.dart';

void main() {
  test(
    'clasificación actual cambia sin modificar costos, nombres e importes históricos',
    () {
      final sales = [sale()];
      final report = CategorySalesReport.calculate(period, sales, [article()]);
      expect(report.categories.single.label, 'Bebidas');
      expect(report.categories.single.totalMinor, BigInt.from(1000));
      expect(report.categories.single.gross.profitMinor, BigInt.from(800));
      expect(
        CategorySalesReport.products(report.categories.single).single.label,
        'Nombre histórico',
      );
      expect(
        CategorySalesReport.calculate(period, sales, [
          article(category: null),
        ]).categories.single.label,
        'Sin categoría',
      );
      expect(
        CategorySalesReport.calculate(
          period,
          sales,
          [],
        ).categories.single.label,
        'Fuera del catálogo actual',
      );
    },
  );
  test(
    'ajustes de venta anterior, exclusiones y beneficio concilian con calculador existente',
    () {
      final sales = [
        sale(),
        sale(
          date: DateTime(2026, 10, 28),
          adjustments: [
            adjustment(),
            adjustment(status: 'rejected'),
            adjustment(status: 'conflict'),
          ],
        ),
      ];
      final group = CategorySalesReport.calculate(period, sales, [
        article(),
      ]).categories.single;
      expect(
        group.totalMinor,
        SalesReportsCalculator.ventasTotales(period, sales),
      );
      expect(
        group.gross.profitMinor,
        SalesReportsCalculator.grossProfit(period, sales).profitMinor,
      );
      expect(group.quantityAtomic, BigInt.one);
      expect(group.entries.length, 2);
      final onlyAdjustment = CategorySalesReport.calculate(
        period,
        [sales.last],
        [article()],
      ).categories.single;
      expect(onlyAdjustment.totalMinor, BigInt.from(-250));
      expect(onlyAdjustment.gross.profitMinor, BigInt.from(-200));
    },
  );
  test(
    'costo cero, desconocido y medido conservan cálculo parcial y redondeo',
    () {
      final sales = [
        sale(
          lines: [
            line(cost: 0),
            line(id: 'other', variant: 'other', cost: null),
            line(id: 'measured', variant: 'm', quantity: null, cost: 101),
          ],
        ),
      ];
      final report = CategorySalesReport.calculate(period, sales, [
        article(variants: ['v', 'other', 'm']),
      ]);
      expect(
        report.categories.single.gross.estado,
        BeneficioBrutoEstado.parcial,
      );
      expect(report.categories.single.gross.profitMinor, BigInt.from(1949));
      expect(
        report.categories.single.gross.vendidoSinCostoMinor,
        BigInt.from(1000),
      );
      expect(
        CategorySalesReport.products(
          report.categories.single,
          byQuantity: true,
        ).first.unit,
        'kg',
      );
    },
  );
  test('límites inclusivos, precisión y suma del desglose', () {
    const amount = 9007199254740991;
    final sales = [
      sale(
        lines: [
          line(total: amount),
          line(id: 'b', variant: 'absent', total: amount),
        ],
      ),
      sale(date: DateTime(2026, 10, 30)),
    ];
    final report = CategorySalesReport.calculate(period, sales, [article()]);
    expect(
      report.categories.fold(BigInt.zero, (n, g) => n + g.totalMinor),
      BigInt.from(amount) * BigInt.two,
    );
    for (final group in report.categories) {
      expect(
        CategorySalesReport.products(
          group,
        ).fold(BigInt.zero, (n, g) => n + g.totalMinor),
        group.totalMinor,
      );
    }
    expect(CategorySalesReport.calculate(period, [], []).categories, isEmpty);
  });
}
