import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/cuenta/declarar_saldo_cuenta_screen.dart';

import '../../../support/cuenta_harness.dart';

void main() {
  late CuentaHarness h;
  setUp(() => h = CuentaHarness());
  tearDown(() => h.dispose());

  Future<void> screen(WidgetTester t, {Size size = const Size(500, 900)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: DeclararSaldoCuentaScreen(
          repository: h.repository,
          commands: h.cuenta,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  /// Captura y declara. Al declararse, la forma desaparece y con ella el cursor
  /// del campo, asi que despues si se puede asentar.
  Future<void> capturar(WidgetTester t, String importe) async {
    await t.enterText(find.byKey(const Key('bank_amount')), importe);
    await t.pump();
    await t.tap(find.byKey(const Key('bank_declare')));
    await t.pumpAndSettle();
  }

  /// Desarma el arbol dentro del test. Al cancelar la consulta, Drift agenda un
  /// `Timer.run` para soltar su cache; con `pump()` sin duracion el reloj de
  /// FakeAsync no avanza, el temporizador sobrevive y el marco marca el test
  /// como fallido. Por eso el pump lleva duracion explicita.
  Future<void> desarmar(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(milliseconds: 1));
  }

  testWidgets('declara el saldo que reporta el banco y lo muestra pendiente', (
    t,
  ) async {
    await screen(t);

    expect(find.textContaining('Todavía no se declara'), findsOneWidget);
    await capturar(t, '1500.50');

    expect(find.byKey(const Key('declared_baseline_card')), findsOneWidget);
    expect(find.text(r'$1500.50'), findsOneWidget);
    expect(find.text('Pendiente de sincronizar'), findsOneWidget);
    // Declarado, no entregado: el hecho existe todavia solo aqui.
    expect((await h.store.only())!.lastServerSequence, isNull);
    await desarmar(t);
  });

  testWidgets('acepta un saldo sobregirado y lo muestra con signo', (t) async {
    await screen(t);
    await capturar(t, '-250.00');

    expect(find.text(r'-$250.00'), findsOneWidget);
    expect((await h.store.only())!.amountMinor, -25000);
    await desarmar(t);
  });

  testWidgets('el chip cambia a sincronizada cuando el servidor lo entrega', (
    t,
  ) async {
    await screen(t);
    await capturar(t, '300.00');

    final eventId = (await h.store.only())!.createdEventId!;
    await h.persistence.updateEventSyncStatus(
      eventId,
      'delivered',
      serverSequence: 9,
    );
    await h.store.acknowledge(eventId, 9);
    await t.pumpAndSettle();

    expect(find.text('Sincronizada'), findsOneWidget);
    // El hecho no se vuelve editable: no hay forma de tocar el importe.
    expect(find.byKey(const Key('bank_amount')), findsNothing);
    expect(find.byKey(const Key('bank_declare')), findsNothing);
    expect(find.textContaining('se declara una sola vez'), findsOneWidget);
    await desarmar(t);
  });

  testWidgets('un rechazo del servidor se marca para revision', (t) async {
    await screen(t);
    await capturar(t, '300.00');

    final eventId = (await h.store.only())!.createdEventId!;
    await h.persistence.updateEventSyncStatus(
      eventId,
      'conflict',
      rejectionReason: 'El saldo inicial ya fue declarado.',
    );
    await t.pumpAndSettle();

    expect(find.text('Requiere atención'), findsOneWidget);
    // El importe declarado no se borra: se ve, marcado, para revisarlo.
    expect(find.text(r'$300.00'), findsOneWidget);
    await desarmar(t);
  });

  testWidgets('no ofrece una segunda declaracion', (t) async {
    await screen(t);
    await capturar(t, '300.00');

    expect(find.byKey(const Key('bank_amount')), findsNothing);
    expect((await h.store.only())!.amountMinor, 30000);
    expect(await h.persistence.pendingEvents(), hasLength(1));
    await desarmar(t);
  });

  testWidgets('un importe invalido no se puede declarar', (t) async {
    await screen(t);
    await t.enterText(find.byKey(const Key('bank_amount')), 'mil');
    await t.pump();
    await t.tap(find.byKey(const Key('bank_declare')));
    await t.pump();

    expect(find.text('Captura un importe válido.'), findsOneWidget);
    expect(await h.store.only(), isNull);
    await desarmar(t);
  });

  testWidgets('con el ajuste apagado avisa y no deja declarar', (t) async {
    h.setBankEnabled(false);
    await screen(t);

    expect(find.textContaining('no está habilitado'), findsOneWidget);
    final button = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Declarar saldo'),
    );
    expect(button.onPressed, isNull);
    await desarmar(t);
  });
}
