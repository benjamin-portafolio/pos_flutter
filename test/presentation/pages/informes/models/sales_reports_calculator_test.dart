import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/informes/models/beneficio_bruto_report.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import 'package:pos_flutter/presentation/pages/informes/models/sales_reports_calculator.dart';
import 'package:pos_flutter/presentation/pages/informes/models/ventas_por_metodo_report.dart';

SaleDraftItem line({
  int? cost,
  int? quantity,
  int? measuredAtomic,
  int? reference,
  int total = 10000,
  String id = 'l',
}) => SaleDraftItem(
  id: id,
  variantId: 'v',
  productName: 'Producto',
  variantName: null,
  quantity: quantity,
  measuredQuantityAtomic: measuredAtomic,
  unitPriceMinor: 1000,
  standardCostMinor: cost,
  priceReferenceQuantityAtomic: reference,
  unitCode: reference == null ? null : 'kg',
  unitSymbol: reference == null ? null : 'kg',
  unitAtomicFactor: reference == null ? null : 1000,
  totalMinor: total,
);

ConfirmedSale sale({
  required DateTime createdAt,
  int total = 0,
  List<SaleDraftItem> items = const [],
  String method = 'cash',
  int received = 0,
  String id = 'sale',
}) => ConfirmedSale(
  id: id,
  paymentMethod: method,
  createdAt: createdAt,
  totalMinor: total,
  receivedMinor: received,
  changeMinor: method == 'cash' ? received - total : 0,
  currency: 'MXN',
  deliveryStatus: 'not_required',
  reason: null,
  items: items,
);

void main() {
  final day = ReportPeriod.day(DateTime(2026, 9, 17));
  final hoy = DateTime(2026, 9, 17, 12);

  group('Beneficio bruto', () {
    test('unitario con costo conocido: total de línea menos costo×cantidad', () {
      final report = SalesReportsCalculator.grossProfit(day, [
        sale(
          createdAt: hoy,
          total: 3200,
          items: [line(quantity: 2, cost: 100, total: 3200)],
        ),
      ]);
      expect(report.estado, BeneficioBrutoEstado.total);
      expect(report.profitMinor, BigInt.from(3000)); // 3200 − 100·2
      expect(report.lineasConCosto, 1);
      expect(report.lineasSinCosto, 0);
      expect(report.monto, r'$30.00 MXN');
    });

    test('medido aplica redondeo half-up al costo de la línea', () {
      final report = SalesReportsCalculator.grossProfit(day, [
        sale(
          createdAt: hoy,
          total: 1000,
          items: [
            // 5 × 5 / 2 = 12.5 → half-up 13
            line(
              measuredAtomic: 5,
              reference: 2,
              cost: 5,
              total: 1000,
            ),
          ],
        ),
      ]);
      expect(report.profitMinor, BigInt.from(987)); // 1000 − 13
    });

    test('costo cero es conocido y válido: beneficio igual al total', () {
      final report = SalesReportsCalculator.grossProfit(day, [
        sale(createdAt: hoy, total: 2500, items: [line(quantity: 1, cost: 0, total: 2500)]),
      ]);
      expect(report.estado, BeneficioBrutoEstado.total);
      expect(report.profitMinor, BigInt.from(2500));
      expect(report.lineasConCosto, 1);
    });

    test('límites: incluye inicio y último instante, excluye extremo abierto', () {
      final report = SalesReportsCalculator.grossProfit(day, [
        sale(
          createdAt: DateTime(2026, 9, 17, 0, 0),
          total: 100,
          items: [line(quantity: 1, cost: 10, total: 100)],
        ),
        sale(
          createdAt: DateTime(2026, 9, 17, 23, 59, 59, 999),
          total: 100,
          items: [line(quantity: 1, cost: 0, total: 100)],
        ),
        sale(
          createdAt: DateTime(2026, 9, 18, 0, 0),
          total: 100,
          items: [line(quantity: 1, cost: 50, total: 100)],
        ),
      ]);
      expect(report.ventasCount, 2);
      expect(report.profitMinor, BigInt.from(190)); // 90 + 100
    });

    test('beneficio negativo se acumula y formatea su signo', () {
      final report = SalesReportsCalculator.grossProfit(day, [
        sale(
          createdAt: hoy,
          total: 500,
          items: [line(quantity: 2, cost: 400, total: 500)],
        ),
      ]);
      expect(report.profitMinor, BigInt.from(-300));
      expect(report.monto, r'-$3.00 MXN');
    });

    test('sin ventas muestra cero en estado total', () {
      final report = SalesReportsCalculator.grossProfit(day, []);
      expect(report.estado, BeneficioBrutoEstado.total);
      expect(report.profitMinor, BigInt.zero);
      expect(report.ventasCount, 0);
      expect(report.monto, r'$0.00 MXN');
    });

    test('costos ausentes producen beneficio parcial con detalle', () {
      final report = SalesReportsCalculator.grossProfit(day, [
        sale(
          createdAt: hoy,
          total: 5000,
          items: [
            line(quantity: 1, cost: 1000, total: 3000),
            line(quantity: 2, cost: null, total: 2000),
          ],
        ),
      ]);
      expect(report.estado, BeneficioBrutoEstado.parcial);
      expect(report.profitMinor, BigInt.from(2000)); // 3000 − 1000
      expect(report.lineasSinCosto, 1);
      expect(report.vendidoSinCostoMinor, BigInt.from(2000));
      expect(report.monto, r'$20.00 MXN');
      expect(report.detalleSinCosto, 'Sin costo: \$20.00 MXN · 1 línea');
    });

    test('sin ningún costo el estado es no disponible', () {
      final report = SalesReportsCalculator.grossProfit(day, [
        sale(
          createdAt: hoy,
          total: 3000,
          items: [line(quantity: 1, cost: null, total: 3000)],
        ),
      ]);
      expect(report.estado, BeneficioBrutoEstado.noDisponible);
      expect(report.monto, isNull);
      expect(report.detalleSinCosto, isNull);
    });

    test('independencia del catálogo: usa el snapshot capturado de cada venta', () {
      final una = SalesReportsCalculator.grossProfit(day, [
        sale(
          id: 'a',
          createdAt: hoy,
          total: 1000,
          items: [line(quantity: 1, cost: 100, total: 1000)],
        ),
      ]);
      final otra = SalesReportsCalculator.grossProfit(day, [
        sale(
          id: 'b',
          createdAt: hoy,
          total: 1000,
          items: [line(quantity: 1, cost: 900, total: 1000)],
        ),
      ]);
      expect(una.profitMinor, BigInt.from(900));
      expect(otra.profitMinor, BigInt.from(100));
    });

    test('acumulación segura con BigInt por encima del límite de int', () {
      const maxInt = 9007199254740991;
      final report = SalesReportsCalculator.grossProfit(day, [
        sale(
          createdAt: hoy,
          total: maxInt,
          items: [line(quantity: 1, cost: 0, total: maxInt)],
        ),
        sale(
          createdAt: hoy,
          total: maxInt,
          items: [line(quantity: 1, cost: 0, total: maxInt)],
        ),
      ]);
      expect(
        report.profitMinor,
        BigInt.from(maxInt) * BigInt.two,
      );
      expect(report.profitMinor > BigInt.from(maxInt), isTrue);
    });
  });

  group('Ventas por método', () {
    test('agrupa efectivo, transferencia y crédito con totalMinor', () {
      final report = SalesReportsCalculator.ventasPorMetodo(day, [
        sale(createdAt: hoy, method: 'cash', total: 1000, received: 5000),
        sale(createdAt: hoy, method: 'cash', total: 2000, received: 3000),
        sale(createdAt: hoy, method: 'transfer', total: 4000, received: 4000),
        sale(createdAt: hoy, method: 'credit', total: 8000),
      ]);
      final cash = report.categoria(MetodoVenta.efectivo)!;
      expect(cash.amountMinor, BigInt.from(3000)); // ignora received/cambio
      expect(cash.ventasCount, 2);
      expect(
        report.categoria(MetodoVenta.transferencia)!.amountMinor,
        BigInt.from(4000),
      );
      expect(
        report.categoria(MetodoVenta.credito)!.amountMinor,
        BigInt.from(8000),
      );
      expect(report.salesCount, 4);
    });

    test('total por métodos coincide exactamente con ventas totales', () {
      final sales = [
        sale(createdAt: hoy, method: 'cash', total: 1000),
        sale(createdAt: hoy, method: 'transfer', total: 2000),
        sale(createdAt: hoy, method: 'credit', total: 3000),
      ];
      final methods = SalesReportsCalculator.ventasPorMetodo(day, sales);
      final total = SalesReportsCalculator.ventasTotales(day, sales);
      expect(methods.totalMinor, total);
      expect(
        methods.categorias.fold(BigInt.zero, (n, c) => n + c.amountMinor),
        total,
      );
    });

    test('método desconocido se agrupa en Otros, no en efectivo', () {
      final report = SalesReportsCalculator.ventasPorMetodo(day, [
        sale(createdAt: hoy, method: 'giftcard', total: 1500),
      ]);
      expect(report.categoria(MetodoVenta.efectivo)!.amountMinor, BigInt.zero);
      expect(report.categoria(MetodoVenta.otros)!.amountMinor, BigInt.from(1500));
      expect(report.totalMinor, BigInt.from(1500));
    });

    test('porcentaje evita dividir entre cero sin ventas', () {
      final report = SalesReportsCalculator.ventasPorMetodo(day, []);
      expect(report.salesCount, 0);
      expect(report.totalMinor, BigInt.zero);
      expect(
        report.categoria(MetodoVenta.efectivo)!.percentOf(BigInt.zero),
        0,
      );
    });

    test('límites del período aplican igual al desglose', () {
      final report = SalesReportsCalculator.ventasPorMetodo(day, [
        sale(createdAt: DateTime(2026, 9, 16, 23, 59, 59), method: 'cash', total: 100),
        sale(createdAt: DateTime(2026, 9, 17), method: 'cash', total: 200),
        sale(createdAt: DateTime(2026, 9, 18), method: 'cash', total: 400),
      ]);
      expect(report.totalMinor, BigInt.from(200));
      expect(report.salesCount, 1);
    });
  });

  group('ReportMoney', () {
    test('formatea importes y signos', () {
      expect(SalesReportsCalculator.ventasTotales(day, []), BigInt.zero);
    });
    test('ventasTotales suma solo el período', () {
      final sales = [
        sale(createdAt: hoy, total: 500),
        sale(createdAt: DateTime(2026, 9, 18), total: 9000),
      ];
      expect(SalesReportsCalculator.ventasTotales(day, sales), BigInt.from(500));
    });
  });
}