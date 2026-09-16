import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/domain/ventas/sale_draft.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_payment_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/models/sale_draft_display.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';

import '../../../support/fake_sale_draft_repository.dart';
import '../../../support/sale_draft_fixtures.dart';

void main() {
  testWidgets(
    'caja muestra líneas, cantidades e importes y deja acciones pendientes deshabilitadas',
    (tester) async {
      _phone(tester);
      await _pump(tester, sampleSale());
      expect(find.textContaining('Test Variantes'), findsNWidgets(3));
      expect(find.text('Test Variantes · Variante 2'), findsOneWidget);
      expect(find.text(r'2 × $42.00'), findsOneWidget);
      expect(find.text(r'$84.00'), findsOneWidget);
      expect(find.text(r'$4.00'), findsOneWidget);
      expect(find.text(r'$21.00'), findsOneWidget);
      expect(find.text(r'$109.00'), findsNWidgets(2));
      expect(find.text('3 artículos · 5 unidades'), findsOneWidget);
      expect(find.textContaining('mesa'), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Añadir artículo nuevo'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, r'Cobrar: $109.00'),
            )
            .onPressed,
        isNotNull,
      );
      for (final button in tester.widgetList<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton && widget.tooltip == 'Código de barras',
        ),
      )) {
        expect(button.onPressed, isNull);
      }
      for (final button in tester.widgetList<TextButton>(
        find.byType(TextButton),
      )) {
        expect(button.onPressed, isNull);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cobrar abre efectivo y regresar conserva la venta', (
    tester,
  ) async {
    _phone(tester);
    final commands = _Commands();
    await _pump(tester, sampleSale(), commands: commands);
    await tester.tap(find.text(r'Cobrar: $109.00'));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentMethodScreen), findsOneWidget);
    expect(find.text('DETALLES DEL CLIENTE (OPCIONAL)'), findsOneWidget);
    expect(find.text('Nombre del cliente'), findsOneWidget);
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enabled, isFalse);
    }
    for (final label in [
      'Tarjeta de débito',
      'Tarjeta de crédito',
      'Transferencia bancaria',
    ]) {
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
      );
    }
    for (final button in tester.widgetList<IconButton>(
      find.byType(IconButton),
    )) {
      if (button.tooltip == 'Buscar cliente' ||
          button.tooltip == 'Más datos del cliente') {
        expect(button.onPressed, isNull);
      }
    }
    await tester.tap(find.text('Efectivo'));
    await tester.pumpAndSettle();
    expect(find.byType(CashPaymentScreen), findsOneWidget);
    expect(find.text(r'$109.00'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '200');
    await tester.pump();
    expect(find.text(r'$91.00'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(r'Cobrar: $109.00'), findsOneWidget);
    expect(find.text('3 artículos · 5 unidades'), findsOneWidget);
    expect(commands.cleared, isEmpty);
  });

  testWidgets('no permite cobrar un borrador sin artículos', (tester) async {
    _phone(tester);
    await _pump(tester, SaleDraft(id: 'empty', totalMinor: 0, items: []));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, r'Cobrar: $0.00'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'limpiar envía la venta concreta, bloquea dobles toques y observa el estado vacío',
    (tester) async {
      _phone(tester);
      final updates = StreamController<SaleDraft?>();
      addTearDown(updates.close);
      final gate = Completer<void>();
      final commands = _Commands()..gate = gate.future;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CajaScreen(
              saleDraftRepository: FakeSaleDraftRepository(() async* {
                yield sampleSale();
                yield* updates.stream;
              }),
              ventaBorradorCommandService: commands,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Limpiar venta'),
        200,
        scrollable: _saleScroll,
      );
      await tester.tap(find.text('Limpiar venta'));
      await tester.pump();
      expect(commands.cleared.single.saleId, 'sale');
      final busy = find.widgetWithText(FilledButton, 'Limpiando…');
      expect(tester.widget<FilledButton>(busy).onPressed, isNull);
      updates.add(null);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('La venta está vacía.'), findsOneWidget);
      expect(find.text(r'Cobrar: $0.00'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, r'Cobrar: $0.00'),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Limpiar venta'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('un fallo al limpiar conserva el detalle y permite reintentar', (
    tester,
  ) async {
    _phone(tester);
    final commands = _Commands()..fail = true;
    await _pump(tester, sampleSale(), commands: commands);
    await tester.scrollUntilVisible(
      find.text('Limpiar venta'),
      200,
      scrollable: _saleScroll,
    );
    await tester.tap(find.text('Limpiar venta'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo limpiar la venta. Intenta nuevamente.'),
      findsOneWidget,
    );
    expect(find.text('3 artículos · 5 unidades'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Limpiar venta'),
          )
          .onPressed,
      isNotNull,
    );
    commands.fail = false;
    await tester.tap(find.text('Limpiar venta'));
    await tester.pumpAndSettle();
    expect(commands.cleared, hasLength(2));
  });

  testWidgets(
    'presenta medidas separadas de piezas con texto ampliado en teléfono estrecho',
    (tester) async {
      _phone(tester, width: 320);
      final sale = SaleDraft(
        id: 'sale',
        totalMinor: 25900,
        items: [...sampleSale().items, measuredSaleItem],
      );
      await _pump(tester, sale, textScale: 2);
      await tester.scrollUntilVisible(
        find.text('0.750 kg × \$200.00 / 1 kg'),
        200,
        scrollable: _saleScroll,
      );
      expect(find.text('0.750 kg × \$200.00 / 1 kg'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('4 artículos · 5 unidades · 0.750 kg'),
        200,
        scrollable: _saleScroll,
      );
      expect(find.text('4 artículos · 5 unidades · 0.750 kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'indicadores acumulan una variante con condiciones distintas y separan medidas',
    () {
      final sale = SaleDraft(
        id: 'sale',
        totalMinor: 51800,
        items: [
          ...sampleSale().items,
          ...sampleSale().items,
          measuredSaleItem,
          measuredSaleItem,
        ],
      );
      expect(sale.articleCount, 4);
      expect(SaleDraftDisplay.badge(sale, 'small'), '×4');
      expect(SaleDraftDisplay.badge(sale, 'measured'), '1.500 kg');
      expect(
        SaleDraftDisplay.summary(sale),
        '4 artículos · 10 unidades · 1.500 kg',
      );
    },
  );
}

Finder get _saleScroll => find.descendant(
  of: find.byType(ListView),
  matching: find.byType(Scrollable),
);

void _phone(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester,
  SaleDraft sale, {
  _Commands? commands,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: CajaScreen(
          saleDraftRepository: FakeSaleDraftRepository(
            () => Stream.value(sale),
          ),
          ventaBorradorCommandService: commands,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Commands implements VentaBorradorCommandService {
  final cleared = <LimpiarVentaBorradorCommand>[];
  Future<void>? gate;
  bool fail = false;

  @override
  Future<void> limpiar(LimpiarVentaBorradorCommand command) async {
    cleared.add(command);
    if (fail) throw StateError('fallo');
    await gate;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
