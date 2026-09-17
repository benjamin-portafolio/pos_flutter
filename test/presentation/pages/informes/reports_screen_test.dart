import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/informes/reports_screen.dart';

class _Repository implements ConfirmedSaleRepository {
  final controller = StreamController<List<ConfirmedSale>>.broadcast();

  @override
  Stream<List<ConfirmedSale>> watchSales() => controller.stream;
}

ConfirmedSale _sale(
  DateTime date,
  int total, {
  String status = 'not_required',
}) => ConfirmedSale(
  id: '$date-$status',
  createdAt: date,
  totalMinor: total,
  receivedMinor: total + 10000,
  changeMinor: 10000,
  currency: 'MXN',
  deliveryStatus: status,
  reason: null,
  items: [],
);

void main() {
  late _Repository repository;
  setUp(() => repository = _Repository());
  tearDown(() => repository.controller.close());

  Future<void> pump(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ReportsScreen(
            repository: repository,
            now: () => DateTime(2026, 9, 17, 12),
          ),
        ),
      ),
    );
    repository.controller.add([]);
    await tester.pumpAndSettle();
  }

  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.calendar_month));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'total reactivo por cobro; incluye incidencias, excluye cambio y otros días',
    (tester) async {
      await pump(tester);
      expect(find.text(r'$0.00 MXN'), findsOneWidget);
      final sales = [
        _sale(DateTime(2026, 9, 16, 23, 59, 59), 80000),
        _sale(DateTime(2026, 9, 17), 1010),
        _sale(DateTime(2026, 9, 17, 12).toUtc(), 20, status: 'pending'),
        _sale(DateTime(2026, 9, 17, 13), 30, status: 'conflict'),
        _sale(DateTime(2026, 9, 17, 14), 40, status: 'rejected'),
        _sale(DateTime(2026, 9, 17, 23, 59, 59, 999), 50, status: 'delivered'),
        _sale(DateTime(2026, 9, 18), 90000),
      ];
      repository.controller.add(sales);
      await tester.pumpAndSettle();
      expect(find.text(r'$11.50 MXN'), findsOneWidget);
      await tester.tap(find.byTooltip('Período anterior'));
      await tester.pumpAndSettle();
      expect(find.text(r'$800.00 MXN'), findsOneWidget);
      await tester.tap(find.byTooltip('Período siguiente'));
      await tester.pumpAndSettle();
      repository.controller.add([
        ...sales,
        _sale(DateTime(2026, 9, 17, 15), 25),
      ]);
      await tester.pumpAndSettle();
      expect(find.text(r'$11.75 MXN'), findsOneWidget);
      await tester.tap(find.text(r'$11.75 MXN'));
      await tester.pumpAndSettle();
      expect(find.byType(ReportsScreen), findsOneWidget);
      expect(find.text('BAJO INVENTARIO DE EXISTENCIAS'), findsOneWidget);
      expect(find.text('EXISTENCIAS RESTANTES'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('Informes de TPV'), findsNothing);
    },
  );

  testWidgets(
    'los ocho accesos rápidos aplican su rango y las flechas conservan su unidad',
    (tester) async {
      await pump(tester);
      repository.controller.add([
        _sale(DateTime(2026, 9, 17), 100),
        _sale(DateTime(2026, 9, 16), 200),
        _sale(DateTime(2026, 9, 10), 400),
        _sale(DateTime(2026, 9, 1), 800),
        _sale(DateTime(2026, 8, 20), 1600),
        _sale(DateTime(2026, 1, 1), 3200),
        _sale(DateTime(2025, 12, 31), 6400),
      ]);
      await tester.pumpAndSettle();
      for (final scenario in [
        ('Hoy', '17 septiembre 2026', r'$1.00 MXN'),
        ('Ayer', '16 septiembre 2026', r'$2.00 MXN'),
        (
          'Esta semana',
          '14 septiembre 2026 – 20 septiembre 2026',
          r'$3.00 MXN',
        ),
        (
          'La semana pasada',
          '7 septiembre 2026 – 13 septiembre 2026',
          r'$4.00 MXN',
        ),
        ('Este mes', '1 septiembre 2026 – 30 septiembre 2026', r'$15.00 MXN'),
        ('El mes pasado', '1 agosto 2026 – 31 agosto 2026', r'$16.00 MXN'),
        ('Este año', '1 enero 2026 – 31 diciembre 2026', r'$63.00 MXN'),
        ('El año pasado', '1 enero 2025 – 31 diciembre 2025', r'$64.00 MXN'),
      ]) {
        await openFilter(tester);
        await tester.scrollUntilVisible(find.text(scenario.$1), 200);
        await tester.pumpAndSettle();
        await tester.tap(find.text(scenario.$1));
        await tester.pumpAndSettle();
        expect(find.text(scenario.$2), findsOneWidget);
        expect(find.text(scenario.$3), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Período siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('1 enero 2026 – 31 diciembre 2026'), findsOneWidget);
      expect(find.text(r'$63.00 MXN'), findsOneWidget);
      await openFilter(tester);
      await tester.scrollUntilVisible(find.text('Este mes'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Este mes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Período anterior'));
      await tester.pumpAndSettle();
      expect(find.text('1 agosto 2026 – 31 agosto 2026'), findsOneWidget);
    },
  );

  testWidgets(
    'calendario aplica rango, muestra el período al pie y permite cancelar',
    (tester) async {
      await pump(tester);
      repository.controller.add([
        _sale(DateTime(2026, 9, 12), 100),
        _sale(DateTime(2026, 9, 17, 23, 59, 59), 200),
        _sale(DateTime(2026, 9, 18), 400),
      ]);
      await tester.pumpAndSettle();
      await openFilter(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-2026-9-12')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Mostrar informes'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-2026-9-17')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Período seleccionado: 12 septiembre 2026 – 17 septiembre 2026',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Mostrar informes'));
      await tester.pumpAndSettle();
      expect(find.text(r'$3.00 MXN'), findsOneWidget);
      await tester.tap(find.byTooltip('Período siguiente'));
      await tester.pumpAndSettle();
      expect(
        find.text('18 septiembre 2026 – 23 septiembre 2026'),
        findsOneWidget,
      );
      expect(find.text(r'$4.00 MXN'), findsOneWidget);
      await openFilter(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-2026-9-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        find.text('18 septiembre 2026 – 23 septiembre 2026'),
        findsOneWidget,
      );
    },
  );

  testWidgets('elige rangos entre meses y un único día', (tester) async {
    await pump(tester);
    await openFilter(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-2026-9-30')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mes siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-2026-10-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mostrar informes'));
    await tester.pumpAndSettle();
    expect(find.text('30 septiembre 2026 – 2 octubre 2026'), findsOneWidget);
    await openFilter(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('calendar-2026-9-3')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Mostrar informes'));
    await tester.pumpAndSettle();
    expect(find.text('3 septiembre 2026'), findsOneWidget);
  });

  testWidgets('error no se muestra como cero y permite reintentar', (
    tester,
  ) async {
    await pump(tester);
    repository.controller.addError(StateError('Sin lectura'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar las ventas.'), findsOneWidget);
    expect(find.text(r'$0.00 MXN'), findsNothing);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    repository.controller.add([_sale(DateTime(2026, 9, 17), 1050)]);
    await tester.pumpAndSettle();
    expect(find.text(r'$10.50 MXN'), findsOneWidget);
  });

  testWidgets(
    'teléfono estrecho y texto grande permiten calendario, accesos y pie',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pump(tester, scale: 2);
      await openFilter(tester);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('El año pasado'), 200);
      await tester.pumpAndSettle();
      expect(find.text('Mostrar informes'), findsOneWidget);
      await tester.tap(find.text('El año pasado'));
      await tester.pumpAndSettle();
      expect(find.text('1 enero 2025 – 31 diciembre 2025'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
