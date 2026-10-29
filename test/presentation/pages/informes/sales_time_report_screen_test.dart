import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import 'package:pos_flutter/presentation/pages/informes/sales_time_detail_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/sales_time_report_screen.dart';

class _Repository implements ConfirmedSaleRepository {
  List<ConfirmedSale> sales = [];
  final updates = StreamController<List<ConfirmedSale>>.broadcast();
  @override
  Stream<List<ConfirmedSale>> watchSales() async* {
    yield sales;
    yield* updates.stream;
  }
}

void main() {
  late _Repository repository;
  setUp(() => repository = _Repository());
  tearDown(() => repository.updates.close());

  ConfirmedSale sale(int hour, int total) => ConfirmedSale(
    id: 'ticket-$hour',
    createdAt: DateTime(2026, 10, 29, hour),
    totalMinor: total,
    receivedMinor: total,
    changeMinor: 0,
    currency: 'MXN',
    deliveryStatus: 'not_required',
    reason: null,
    items: [],
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SalesTimeReportScreen(
          initialPeriod: ReportPeriod.day(DateTime(2026, 10, 29)),
          repository: repository,
          now: () => DateTime(2026, 10, 29),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'hora → operaciones → ticket; vuelve y cambia agrupación y período',
    (tester) async {
      repository.sales = [sale(9, 12300), sale(11, 200)];
      await pump(tester);
      expect(find.text(r'$125.00 MXN'), findsWidgets);
      await tester.tap(find.text('09:00 – 10:00').last);
      await tester.pumpAndSettle();
      expect(find.byType(SalesTimeDetailScreen), findsOneWidget);
      expect(find.text('Venta ticket-9'), findsOneWidget);
      expect(find.text('Venta ticket-11'), findsNothing);
      await tester.tap(find.text('Venta ticket-9'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SaleReceiptScreen), findsOneWidget);
      expect(
        tester.widget<SaleReceiptScreen>(find.byType(SaleReceiptScreen)).saleId,
        'ticket-9',
      );
      await tester.tap(find.text('Volver al reporte'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Día de la semana'));
      await tester.pumpAndSettle();
      expect(find.text('Jueves'), findsWidgets);
      await tester.tap(find.text('Mensual'));
      await tester.pumpAndSettle();
      expect(find.text('octubre 2026'), findsWidgets);
      await tester.tap(find.byTooltip('Período anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Sin ventas en este período'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Hoy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hoy'));
      await tester.pumpAndSettle();
      expect(find.text(r'$125.00 MXN'), findsWidgets);
    },
  );

  testWidgets('carga, vacío, cambios reactivos y recuperación tras error', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Sin ventas en este período'), findsOneWidget);
    repository.sales = [sale(8, 450)];
    repository.updates.add(repository.sales);
    await tester.pumpAndSettle();
    expect(find.text(r'$4.50 MXN'), findsAtLeastNWidgets(2));
    repository.updates.addError(StateError('offline read failed'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar las ventas.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text(r'$4.50 MXN'), findsAtLeastNWidgets(2));
  });
  testWidgets('reporte en teléfono con texto ampliado', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository.sales = [sale(9, 1234567), sale(11, 200)];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.8)),
          child: child!,
        ),
        home: SalesTimeReportScreen(
          initialPeriod: ReportPeriod.day(DateTime(2026, 10, 29)),
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
