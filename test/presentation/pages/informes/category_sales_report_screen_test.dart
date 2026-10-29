import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/category_sales_report_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import '../../../support/fake_reports_producto_repository.dart';
import '../../../support/category_sales_fixtures.dart' as fixtures;

class _Repository implements ConfirmedSaleRepository {
  List<ConfirmedSale> sales = [fixtures.sale()];
  final controller = StreamController<List<ConfirmedSale>>.broadcast();
  @override
  Stream<List<ConfirmedSale>> watchSales() async* {
    yield sales;
    yield* controller.stream;
  }
}

void main() {
  late _Repository repository;
  late FakeReportsProductoRepository products;
  setUp(() {
    repository = _Repository();
    products = FakeReportsProductoRepository()..articles = [fixtures.article()];
  });
  tearDown(() async {
    await repository.controller.close();
    await products.controller.close();
  });
  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: CategorySalesReportScreen(
          initialPeriod: ReportPeriod.day(DateTime(2026, 10, 29)),
          repository: repository,
          productoRepository: products,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('categoría → artículo → ticket; conserva período y vuelve', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('BENEFICIO BRUTO TOTAL'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Bebidas').last, 250);
    await tester.ensureVisible(find.text('Bebidas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bebidas').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ordenar por cantidad'), 250);
    await tester.ensureVisible(find.text('Ordenar por cantidad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ordenar por cantidad'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Nombre histórico').last, 250);
    await tester.ensureVisible(find.text('Nombre histórico').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombre histórico').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Venta ticket'), 250);
    await tester.ensureVisible(find.text('Venta ticket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Venta ticket'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<SaleReceiptScreen>(find.byType(SaleReceiptScreen)).saleId,
      'ticket',
    );
    await tester.tap(find.text('Volver al reporte'));
    await tester.pumpAndSettle();
    expect(find.text('Venta ticket'), findsOneWidget);
  });
  testWidgets(
    'actualizaciones del catálogo, errores, reintento y período vacío',
    (tester) async {
      await pump(tester);
      products.emit([]);
      await tester.pumpAndSettle();
      expect(find.text('Fuera del catálogo actual'), findsWidgets);
      repository.controller.addError(StateError('error'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudo cargar el informe.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Fuera del catálogo actual'), findsWidgets);
      await tester.tap(find.byTooltip('Período anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Sin operaciones en este período'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      expect(find.text('Mostrar informes'), findsOneWidget);
    },
  );
  testWidgets('teléfono estrecho y texto ampliado', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, scale: 1.8);
    await tester.drag(find.byType(ListView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
