import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';
import 'package:pos_flutter/presentation/pages/hoy/today_sales_screen.dart';

import '../../../support/pump_receipt_image.dart';
import '../../../support/sale_draft_fixtures.dart';

class _Repository implements ConfirmedSaleRepository {
  _Repository(this.read);
  final Stream<List<ConfirmedSale>> Function() read;

  @override
  Stream<List<ConfirmedSale>> watchSales() => read();
}

ConfirmedSale _sale(
  String id,
  DateTime date, {
  String method = 'cash',
  int total = 10000,
  String? client,
}) => ConfirmedSale(
  id: id,
  createdAt: date,
  totalMinor: total,
  receivedMinor: method == 'cash' ? total + 5000 : 0,
  changeMinor: method == 'cash' ? 5000 : 0,
  paymentMethod: method,
  clienteNombre: client,
  currency: 'MXN',
  deliveryStatus: 'not_required',
  reason: null,
  items: sampleSale().items,
);

Finder _tile(String id) => find.byKey(ValueKey('today-sale-$id'));

Future<void> _pump(
  WidgetTester tester,
  ConfirmedSaleRepository repository, {
  DateTime Function()? now,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TodaySalesScreen(
          repository: repository,
          now: now ?? () => DateTime(2026, 10, 28, 15),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('incluye solo el día local, ordena y suma el monto vendido', (
    tester,
  ) async {
    final sales = [
      _sale('previous', DateTime(2026, 10, 27, 23, 59, 59)),
      _sale('start', DateTime(2026, 10, 28).toUtc()),
      _sale('next', DateTime(2026, 10, 29)),
      _sale(
        'last',
        DateTime(2026, 10, 28, 23, 59, 59),
        method: 'credit',
        total: 30000,
        client: 'María López',
      ),
    ];
    await _pump(tester, _Repository(() => Stream.value(sales)));
    await tester.pumpAndSettle();
    expect(find.text('Hoy · 28 octubre 2026'), findsOneWidget);
    expect(find.text('2 ventas'), findsOneWidget);
    expect(find.text(r'$400.00 MXN'), findsOneWidget);
    expect(_tile('previous'), findsNothing);
    expect(_tile('next'), findsNothing);
    expect(
      tester.getTopLeft(_tile('last')).dy,
      lessThan(tester.getTopLeft(_tile('start')).dy),
    );
    expect(find.textContaining('María López'), findsOneWidget);
    expect(find.textContaining('Público general'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('A crédito'), findsOneWidget);
  });

  testWidgets('filtra sin cambiar el resumen y recibe nuevas ventas', (
    tester,
  ) async {
    final stream = StreamController<List<ConfirmedSale>>();
    addTearDown(stream.close);
    final sales = [
      _sale('cash', DateTime(2026, 10, 28, 12)),
      _sale('credit', DateTime(2026, 10, 28, 13), method: 'credit'),
    ];
    await _pump(tester, _Repository(() => stream.stream));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    stream.add(sales);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Crédito'));
    await tester.pumpAndSettle();
    expect(_tile('cash'), findsNothing);
    expect(_tile('credit'), findsOneWidget);
    expect(find.text('2 ventas'), findsOneWidget);
    expect(find.text(r'$200.00 MXN'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Transferencia'));
    await tester.pumpAndSettle();
    expect(find.text('No hay ventas de este método hoy.'), findsOneWidget);
    stream.add([
      ...sales,
      _sale('new', DateTime(2026, 10, 28, 14), method: 'transfer'),
    ]);
    await tester.pumpAndSettle();
    expect(_tile('new'), findsOneWidget);
    expect(find.text('3 ventas'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Todas'));
    await tester.pumpAndSettle();
    expect(_tile('credit'), findsOneWidget);
    expect(_tile('new'), findsOneWidget);
  });

  testWidgets('muestra vacío y permite reintentar una lectura fallida', (
    tester,
  ) async {
    var attempts = 0;
    await _pump(
      tester,
      _Repository(() {
        attempts++;
        return attempts == 1
            ? Stream.error(StateError('Lectura fallida'))
            : Stream.value([]);
      }),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudieron cargar las ventas de hoy.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Todavía no hay ventas hoy.'), findsOneWidget);
    expect(find.text('0 ventas'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('cambia de día a medianoche y al reanudar la app', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 28, 23, 59, 59);
    await _pump(
      tester,
      _Repository(
        () => Stream.value([
          _sale('today', DateTime(2026, 10, 28, 12)),
          _sale('tomorrow', DateTime(2026, 10, 29)),
        ]),
      ),
      now: () => now,
    );
    await tester.pumpAndSettle();
    expect(_tile('today'), findsOneWidget);
    now = DateTime(2026, 10, 29);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(_tile('today'), findsNothing);
    expect(_tile('tomorrow'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 10, 30, 10);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Hoy · 30 octubre 2026'), findsOneWidget);
    expect(find.text('Todavía no hay ventas hoy.'), findsOneWidget);
  });

  testWidgets('abre el ticket seleccionado y vuelve al filtro de Hoy', (
    tester,
  ) async {
    final sales = [
      _sale(
        'receipt',
        DateTime(2026, 10, 28, 14),
        method: 'credit',
        client: 'María López',
      ),
    ];
    await _pump(tester, _Repository(() => Stream.value(sales)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Crédito'));
    await tester.pumpAndSettle();
    await tester.tap(_tile('receipt'));
    await pumpReceiptImage(tester);
    expect(find.byType(SaleReceiptScreen), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, contains('Recibo receipt'));
    expect(image.semanticLabel, contains('Cliente: María López'));
    expect(find.text('Nueva venta'), findsNothing);
    await tester.tap(find.text('Volver a Hoy'));
    await tester.pumpAndSettle();
    expect(find.byType(SaleReceiptScreen), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Crédito'))
          .selected,
      isTrue,
    );
  });

  testWidgets('se adapta a un teléfono angosto', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(
      tester,
      _Repository(
        () => Stream.value([_sale('small', DateTime(2026, 10, 28, 12))]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(_tile('small'), 100);
    expect(tester.takeException(), isNull);
  });
}
