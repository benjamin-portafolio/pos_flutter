import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/informes/reports_screen.dart';

class _Repository implements ConfirmedSaleRepository {
  final controller = StreamController<List<ConfirmedSale>>.broadcast();
  @override
  Stream<List<ConfirmedSale>> watchSales() => controller.stream;
}

SaleDraftItem _line({
  int? cost,
  int quantity = 1,
  int total = 10000,
}) => SaleDraftItem(
  id: 'line-$cost-$quantity-$total',
  variantId: 'v',
  productName: 'Producto',
  variantName: null,
  quantity: quantity,
  measuredQuantityAtomic: null,
  unitPriceMinor: 1000,
  standardCostMinor: cost,
  priceReferenceQuantityAtomic: null,
  unitCode: null,
  unitSymbol: null,
  unitAtomicFactor: null,
  totalMinor: total,
);

ConfirmedSale _sale({
  required DateTime date,
  required List<SaleDraftItem> items,
  int total = 0,
}) => ConfirmedSale(
  id: 'sale-$date',
  createdAt: date,
  totalMinor: total,
  receivedMinor: total,
  changeMinor: 0,
  currency: 'MXN',
  deliveryStatus: 'not_required',
  reason: null,
  items: items,
);

void main() {
  late _Repository repository;
  setUp(() => repository = _Repository());
  tearDown(() => repository.controller.close());

  Future<void> pump(WidgetTester tester, List<ConfirmedSale> sales) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsScreen(
            repository: repository,
            now: () => DateTime(2026, 9, 17, 12),
          ),
        ),
      ),
    );
    repository.controller.add(sales);
    await tester.pumpAndSettle();
  }

  testWidgets('todas las líneas con costo muestran beneficio bruto total', (
    tester,
  ) async {
    await pump(tester, [
      _sale(
        date: DateTime(2026, 9, 17, 12),
        total: 3200,
        items: [_line(cost: 100, total: 3200)],
      ),
      _sale(
        date: DateTime(2026, 9, 17, 13),
        total: 0,
        items: [_line(cost: 0, total: 0)],
      ),
    ]);
    expect(find.text('BENEFICIO BRUTO TOTAL'), findsOneWidget);
    expect(find.text(r'$31.00 MXN'), findsOneWidget); // 3200 − 100
    expect(
      find.text('Calculado con el costo estándar registrado en la venta.'),
      findsOneWidget,
    );
    expect(find.text('BENEFICIO BRUTO PARCIAL'), findsNothing);
  });

  testWidgets('líneas sin costo muestran beneficio parcial con su detalle', (
    tester,
  ) async {
    await pump(tester, [
      _sale(
        date: DateTime(2026, 9, 17, 12),
        total: 5000,
        items: [
          _line(cost: 1000, total: 3000),
          _line(cost: null, total: 2000),
        ],
      ),
    ]);
    expect(find.text('BENEFICIO BRUTO PARCIAL'), findsOneWidget);
    expect(find.text(r'$20.00 MXN'), findsOneWidget);
    // El detalle de ventas totales también muestra $50.00; aquí el parcial
    // reporta el importe vendido sin costo.
    expect(find.text('Sin costo: \$20.00 MXN · 1 línea'), findsOneWidget);
  });

  testWidgets('ninguna línea con costo muestra no disponible', (tester) async {
    await pump(tester, [
      _sale(
        date: DateTime(2026, 9, 17, 12),
        total: 3000,
        items: [_line(cost: null, total: 3000)],
      ),
    ]);
    expect(find.text('NO DISPONIBLE'), findsOneWidget);
    expect(
      find.text('Las líneas de este período no registran el costo estándar.'),
      findsOneWidget,
    );
  });

  testWidgets('beneficio negativo formatea su signo', (tester) async {
    await pump(tester, [
      _sale(
        date: DateTime(2026, 9, 17, 12),
        total: 500,
        items: [_line(cost: 400, quantity: 2, total: 500)],
      ),
    ]);
    expect(find.text('BENEFICIO BRUTO TOTAL'), findsOneWidget);
    expect(find.text(r'-$3.00 MXN'), findsOneWidget);
  });

  testWidgets('la tarjeta respeta el período seleccionado y es reactiva', (
    tester,
  ) async {
    final current = <ConfirmedSale>[
      _sale(
        date: DateTime(2026, 9, 16, 12),
        total: 3000,
        items: [_line(cost: 1000, total: 3000)],
      ),
      _sale(
        date: DateTime(2026, 9, 17, 12),
        total: 1000,
        items: [_line(cost: 100, total: 1000)],
      ),
    ];
    await pump(tester, current);
    expect(find.text(r'$9.00 MXN'), findsOneWidget); // 1000 − 100
    await tester.tap(find.byTooltip('Período anterior'));
    await tester.pumpAndSettle();
    expect(find.text(r'$20.00 MXN'), findsOneWidget); // 3000 − 1000
    current.add(
      _sale(
        date: DateTime(2026, 9, 17, 13),
        total: 1100,
        items: [_line(cost: 100, total: 1100)],
      ),
    );
    repository.controller.add(List.of(current));
    await tester.tap(find.byTooltip('Período siguiente'));
    await tester.pumpAndSettle();
    expect(find.text(r'$19.00 MXN'), findsOneWidget); // 1000+1100 − 200
  });

  testWidgets('el error de lectura aplica a ambas tarjetas', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsScreen(
            repository: repository,
            now: () => DateTime(2026, 9, 17, 12),
          ),
        ),
      ),
    );
    repository.controller.addError(StateError('Sin lectura'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar las ventas.'), findsOneWidget);
    expect(find.text(r'$0.00 MXN'), findsNothing);
  });
}