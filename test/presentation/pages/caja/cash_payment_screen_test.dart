import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_payment_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';

void main() {
  testWidgets('calcula cambio, importe exacto y faltante como en el video', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(r'$855.00'), findsOneWidget);
    expect(find.text('Cambio'), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Recibido por efectivo'),
          )
          .onPressed,
      isNull,
    );
    for (final scenario in [
      ('900', 'Cambio a dar', r'$45.00'),
      ('92', 'Efectivo pendiente', r'-$763.00'),
      ('920', 'Cambio a dar', r'$65.00'),
      ('855', 'Cambio', r'$0.00'),
      ('0', 'Efectivo pendiente', r'-$855.00'),
      ('', 'Cambio', r'$0.00'),
    ]) {
      await tester.enterText(find.byType(TextField), scenario.$1);
      await tester.pump();
      expect(find.text(scenario.$2), findsOneWidget);
      expect(find.text(scenario.$3), findsOneWidget);
    }
  });

  testWidgets('acepta centavos con punto o coma sin redondeos', (tester) async {
    await _pump(tester, totalMinor: 1010);
    for (final amount in ['10.30', '10,30']) {
      await tester.enterText(find.byType(TextField), amount);
      await tester.pump();
      expect(find.text(r'$0.20'), findsOneWidget);
    }
    await tester.enterText(find.byType(TextField), '.5');
    await tester.pump();
    expect(find.text(r'-$9.60'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '10.');
    await tester.pump();
    expect(find.text(r'-$0.10'), findsOneWidget);
    for (final invalid in ['-20', 'abc', '12.345', '12,3.4']) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '10.',
      );
      expect(find.text(r'-$0.10'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('suma denominaciones desde cero y sobre el importe capturado', (
    tester,
  ) async {
    await _pump(tester);
    for (final scenario in [
      (20, '20.00'),
      (50, '70.00'),
      (100, '170.00'),
      (200, '370.00'),
      (500, '870.00'),
      (1000, '1870.00'),
    ]) {
      await tester.tap(find.text('+ \$${scenario.$1}'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        scenario.$2,
      );
    }
    expect(find.text(r'$1015.00'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '900.25');
    await tester.tap(find.text(r'+ $20'));
    await tester.pump();
    expect(find.text(r'$65.25'), findsOneWidget);
  });

  testWidgets('se adapta a teléfono estrecho, texto grande y teclado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const PaymentMethodScreen(totalMinor: 85500),
      ),
    );
    await tester.pumpAndSettle();
    final pageScroll = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Efectivo'),
      150,
      scrollable: pageScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Efectivo'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '920');
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text(r'$65.00'),
      100,
      scrollable: pageScroll,
    );
    await tester.pumpAndSettle();
    expect(find.text(r'$65.00'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(r'+ $1000'),
      100,
      scrollable: pageScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'+ $1000'));
    await tester.pump();
    expect(find.text('Recibido por efectivo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, {int totalMinor = 85500}) async {
  await tester.pumpWidget(
    MaterialApp(home: CashPaymentScreen(totalMinor: totalMinor)),
  );
  await tester.pumpAndSettle();
}
