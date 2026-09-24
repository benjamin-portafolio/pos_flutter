import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import 'package:pos_flutter/presentation/pages/informes/reports_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/sales_by_method_detail_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/sales_by_method_screen.dart';

class _Repository implements ConfirmedSaleRepository {
  final controller = StreamController<List<ConfirmedSale>>.broadcast();
  @override
  Stream<List<ConfirmedSale>> watchSales() => controller.stream;
}

ConfirmedSale _sale({
  required DateTime date,
  String method = 'cash',
  int total = 0,
  int received = 0,
}) => ConfirmedSale(
  id: 'sale-$date-$method',
  paymentMethod: method,
  createdAt: date,
  totalMinor: total,
  receivedMinor: method == 'cash' ? received : (method == 'transfer' ? total : 0),
  changeMinor: method == 'cash' ? received - total : 0,
  currency: 'MXN',
  deliveryStatus: 'not_required',
  reason: null,
  items: const [],
);

void main() {
  final hoy = DateTime(2026, 9, 17, 12);

  /// Levanta la pantalla sin datos: el stream de prueba aún no ha emitido, así
  /// que el indicador de carga sigue animando. Cada prueba debe emitir con
  /// `controller.add(...)` y luego hacer `pumpAndSettle`.
  Future<void> pumpScreen(
    WidgetTester tester,
    Stream<List<ConfirmedSale>> sales, {
    ReportPeriod? period,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SalesByMethodScreen(
          initialPeriod: period ?? ReportPeriod.day(DateTime(2026, 9, 17)),
          sales: sales,
          now: () => DateTime(2026, 9, 17, 12),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('desglose y total general coinciden con ventas totales', (
    tester,
  ) async {
    final controller = StreamController<List<ConfirmedSale>>.broadcast();
    addTearDown(controller.close);
    await pumpScreen(tester, controller.stream);
    controller.add([
      _sale(date: hoy, method: 'cash', total: 1000, received: 5000),
      _sale(date: hoy, method: 'transfer', total: 2000),
      _sale(date: hoy, method: 'credit', total: 7000),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('TOTAL GENERAL'), findsOneWidget);
    expect(find.text(r'$100.00 MXN'), findsWidgets);
    // Efectivo usa el importe aplicado, no el recibido antes del cambio.
    expect(find.text(r'$10.00 MXN · 1 venta'), findsOneWidget);
    expect(find.text(r'$20.00 MXN · 1 venta'), findsOneWidget);
    expect(find.text(r'$70.00 MXN · 1 venta'), findsOneWidget);
    expect(find.text('10.0%'), findsNWidgets(2)); // gráfica y desglose
    expect(find.text('70.0%'), findsNWidgets(2));
  });

  testWidgets('método desconocido se muestra aparte, no como efectivo', (
    tester,
  ) async {
    final controller = StreamController<List<ConfirmedSale>>.broadcast();
    addTearDown(controller.close);
    await pumpScreen(tester, controller.stream);
    controller.add([_sale(date: hoy, method: 'giftcard', total: 1500)]);
    await tester.pumpAndSettle();

    expect(find.text('Otros métodos'), findsWidgets);
    expect(find.text(r'$15.00 MXN · 1 venta'), findsOneWidget);
    expect(find.text(r'$0.00 MXN · 0 ventas'), findsNWidgets(3)); // efectivo, transferencia, crédito
    expect(find.text(r'$15.00 MXN'), findsWidgets); // total general
  });

  testWidgets('sin ventas muestra estado vacío y total cero', (tester) async {
    final controller = StreamController<List<ConfirmedSale>>.broadcast();
    addTearDown(controller.close);
    await pumpScreen(tester, controller.stream);
    controller.add([]);
    await tester.pumpAndSettle();

    expect(find.text('Sin ventas en este período'), findsOneWidget);
    expect(find.text(r'$0.00 MXN'), findsWidgets);
    expect(find.text(r'$0.00 MXN · 0 ventas'), findsNWidgets(3));
  });

  testWidgets('error con reintento y actualización reactiva', (tester) async {
    final controller = StreamController<List<ConfirmedSale>>.broadcast();
    addTearDown(controller.close);
    await pumpScreen(tester, controller.stream);
    controller.addError(StateError('Sin lectura'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar las ventas.'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    // Reintentar vuelve a suscribirse; el stream broadcast no repite valores
    // anteriores, así que el indicador de carga vuelve a animar sin datos.
    await tester.pump();
    controller.add([_sale(date: hoy, method: 'cash', total: 4000)]);
    await tester.pumpAndSettle();
    expect(find.text(r'$40.00 MXN'), findsWidgets);

    // Actualización reactiva al agregar otra venta.
    controller.add([
      _sale(date: hoy, method: 'cash', total: 4000),
      _sale(date: hoy, method: 'transfer', total: 2000),
    ]);
    await tester.pumpAndSettle();
    expect(find.text(r'$60.00 MXN'), findsWidgets);
  });

  testWidgets('elegir una categoría abre el detalle de sus ventas', (
    tester,
  ) async {
    final controller = StreamController<List<ConfirmedSale>>.broadcast();
    addTearDown(controller.close);
    await pumpScreen(tester, controller.stream);
    controller.add([
      _sale(date: hoy, method: 'cash', total: 1000),
      _sale(date: hoy, method: 'credit', total: 7000),
    ]);
    await tester.pumpAndSettle();

    // La ficha queda bajo el pliegue: se desplaza antes de pulsarla.
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Crédito'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Crédito'));
    // La pantalla de detalle se suscribe al mismo stream broadcast sin reemisión
    // de datos: se debe emitir de nuevo antes de cerrar la animación.
    await tester.pump();
    controller.add([
      _sale(date: hoy, method: 'cash', total: 1000),
      _sale(date: hoy, method: 'credit', total: 7000),
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(SalesByMethodDetailScreen), findsOneWidget);
    expect(find.text('Ventas · Crédito'), findsOneWidget);
    expect(find.text('17 septiembre 2026 · 1 venta'), findsOneWidget);
    expect(find.textContaining('Método: Crédito'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SalesByMethodScreen), findsOneWidget);
  });

  testWidgets('el filtro de Informes se conserva al volver de la pantalla', (
    tester,
  ) async {
    final repository = _Repository();
    addTearDown(repository.controller.close);
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
    repository.controller.add([
      _sale(date: DateTime(2026, 9, 16, 12), method: 'cash', total: 3000),
      _sale(date: hoy, method: 'transfer', total: 1000),
    ]);
    await tester.pumpAndSettle();
    expect(find.text(r'$10.00 MXN'), findsOneWidget); // ventas totales del día

    await tester.tap(find.text('Ver ventas por método'));
    // La pantalla nueva se suscribe al mismo stream broadcast: sin datos aún,
    // muestra su indicador de carga mientras avanza la transición.
    await tester.pump();
    await tester.pump();
    expect(find.byType(SalesByMethodScreen), findsOneWidget);
    // El stream broadcast no repite el último valor a un nuevo suscriptor.
    repository.controller.add([
      _sale(date: DateTime(2026, 9, 16, 12), method: 'cash', total: 3000),
      _sale(date: hoy, method: 'transfer', total: 1000),
    ]);
    await tester.pumpAndSettle();
    expect(find.text(r'$10.00 MXN'), findsWidgets); // total general

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ReportsScreen), findsOneWidget);
    expect(find.text('17 septiembre 2026'), findsOneWidget);
    expect(find.text(r'$10.00 MXN'), findsOneWidget);
  });
}