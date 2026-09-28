import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/repositories/cash_repository_impl.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/transfer_summary.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_management_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/saldo_cuenta_estimado_card.dart';

import '../../../support/cash_harness.dart';
import '../../../support/fake_account_balance_baseline_repository.dart';
import '../../../support/fake_transfer_summary_repository.dart';

void main() {
  // Foto declarada en 2023-11-14T22:13:20Z. Los instantes de prueba se
  // juegan a uno y otro lado de este corte, nunca con fechas reales.
  const asOf = 1700000000000;

  const card = Key('saldo_cuenta_estimado_card');

  TransferMovement movimiento({
    required String id,
    required int amountMinor,
    required int occurredAtMs,
    required FinancialDirection direction,
  }) => TransferMovement(
    id: id,
    eventId: 'event-$id',
    origin: TransferOrigin.financialEntry,
    method: 'transfer',
    amountMinor: amountMinor,
    occurredAtMs: occurredAtMs,
    direction: direction,
  );

  /// Foto de 250,000.00 con: +1,000.00 y -500.00 posteriores a la foto, y
  /// +700.00 anterior que la foto ya cubre. Objetivo: estimado 250,500.00,
  /// dos incluidos y uno excluido en silencio.
  TransferSummary movimientos(int fromMs, int toMs) =>
      TransferSummary.fromMovements(
        fromMs: fromMs,
        toMs: toMs,
        movements: [
          movimiento(
            id: 'in-1',
            amountMinor: 100000,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.income,
          ),
          movimiento(
            id: 'out-1',
            amountMinor: 50000,
            occurredAtMs: asOf + 1,
            direction: FinancialDirection.expense,
          ),
          movimiento(
            id: 'prev-1',
            amountMinor: 70000,
            occurredAtMs: asOf - 1,
            direction: FinancialDirection.income,
          ),
        ],
      );

  FakeAccountBalanceBaselineRepository conBaseline({int amountMinor = 25000000}) =>
      FakeAccountBalanceBaselineRepository(
        baselinePrueba(amountMinor: amountMinor, asOfMs: asOf),
      );

  Future<void> screen(
    WidgetTester t,
    CashHarness h,
    FakeTransferSummaryRepository transfers,
    FakeAccountBalanceBaselineRepository baselines, {
    Size size = const Size(1280, 2400),
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: CashManagementScreen(
          repository: CashRepositoryImpl(h.db),
          commands: h.cash,
          transfers: transfers,
          baselines: baselines,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Finder enCard(String text) =>
      find.descendant(of: find.byKey(card), matching: find.text(text));

  /// Desarma el arbol dentro del test: Drift agenda un timer al cancelar, y
  /// sin un pump con duracion el FakeAsync lo marca como fallido.
  Future<void> desarmar(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  }

  testWidgets(
    'con saldo declarado conviven flujo y stock con etiquetas distintas',
    (t) async {
      final h = CashHarness();
      addTearDown(h.dispose);
      await h.open(amount: 20000);
      await screen(
        t,
        h,
        FakeTransferSummaryRepository(movimientos),
        conBaseline(),
      );

      // El flujo del periodo, intacto en su bloque con su etiqueta.
      expect(find.text('Transferencias · movimiento del periodo'), findsOneWidget);
      // El stock, en su bloque, con la suya: nunca se llaman igual.
      expect(find.text('Saldo en cuenta'), findsOneWidget);
      expect(enCard('Saldo estimado'), findsOneWidget);
      expect(enCard(r'$250500.00'), findsOneWidget);
      expect(
        find.textContaining('Saldo declarado al'),
        findsOneWidget,
      );
      expect(enCard('Entradas posteriores'), findsOneWidget);
      expect(enCard('Salidas posteriores'), findsOneWidget);
      expect(enCard(r'$1000.00'), findsOneWidget);
      expect(enCard(r'$500.00'), findsOneWidget);
      // El movimiento anterior a la foto cuenta, en silencio, para que el
      // desplazamiento no sea invisible.
      expect(
        find.textContaining('2 movimientos posteriores a la foto'),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 anteriores ya estaban en la foto'),
        findsOneWidget,
      );
      await desarmar(t);
    },
  );

  testWidgets('el total en fondos solo con saldo declarado y efectivo esperado', (
    t,
  ) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    await h.open(amount: 20000);
    await screen(
      t,
      h,
      FakeTransferSummaryRepository(movimientos),
      conBaseline(),
    );

    // Efectivo esperado 200.00 + saldo estimado 250,500.00 = 250,700.00.
    expect(find.text('Total en fondos (registrado)'), findsOneWidget);
    expect(enCard(r'$250700.00'), findsOneWidget);
    // La etiqueta lleva "registrado" y la nota aclara que no es ni un saldo
    // exacto ni utilidad: las dos cifras son de instantes distintos.
    expect(
      find.textContaining('no es un saldo exacto ni utilidad'),
      findsOneWidget,
    );
    expect(find.textContaining('utilidad'), findsOneWidget);
    await desarmar(t);
  });

  testWidgets('sin saldo inicial hay aviso con forma de declararlo, no total', (
    t,
  ) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    await h.open();
    await screen(
      t,
      h,
      FakeTransferSummaryRepository(emptyTransferSummary),
      FakeAccountBalanceBaselineRepository(),
    );

    expect(
      find.textContaining('Todavía no se declara el saldo inicial'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('declarar_saldo_inicial')),
      findsOneWidget,
    );
    // Nunca un total parcial: ni estimado, ni total, ni cifras combinadas.
    expect(find.text('Saldo estimado'), findsNothing);
    expect(find.text('Total en fondos (registrado)'), findsNothing);
    expect(enCard(r'$250500.00'), findsNothing);
    // El aviso explica que sin la foto solo queda el flujo del periodo.
    expect(find.textContaining('solo se muestra cuánto entró y salió'), findsOneWidget);
    expect(find.text('Transferencias · movimiento del periodo'), findsOneWidget);
    await desarmar(t);
  });

  testWidgets('el aviso lleva a declarar el saldo inicial', (t) async {
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaldoCuentaEstimadoCard(
            transfers: FakeTransferSummaryRepository(emptyTransferSummary),
            baselines: FakeAccountBalanceBaselineRepository(),
            onDeclareTap: () => taps++,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    await t.tap(find.byKey(const Key('declarar_saldo_inicial')));
    await t.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('la conciliacion es efimera: diferencia con signo y sin persistir', (
    t,
  ) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    await h.open(amount: 20000);
    await screen(
      t,
      h,
      FakeTransferSummaryRepository(movimientos),
      conBaseline(),
    );

    expect(find.textContaining('no se guarda'), findsOneWidget);
    // El banco reporta 251,000.00 contra un estimado de 250,500.00: la
    // diferencia se ve en pantalla al capturarla.
    await t.enterText(
      find.byKey(const Key('conciliacion_saldo_real')),
      '251000.00',
    );
    await t.pumpAndSettle();
    expect(
      t
          .widget<Text>(find.byKey(const Key('conciliacion_diferencia')))
          .data,
      'Diferencia (real − estimado): \$500.00',
    );

    // Y con signo cuando el banco reporta menos: 250,000.00 - 250,500.00.
    await t.enterText(
      find.byKey(const Key('conciliacion_saldo_real')),
      '250000.00',
    );
    await t.pumpAndSettle();
    expect(
      t
          .widget<Text>(find.byKey(const Key('conciliacion_diferencia')))
          .data!
          .contains(r'-$500.00'),
      isTrue,
    );
    await desarmar(t);
  });

  testWidgets('sin sesion de caja no hay total aunque el saldo este declarado', (
    t,
  ) async {
    final h = CashHarness(mode: AppMode.standalone);
    addTearDown(h.dispose);
    await screen(
      t,
      h,
      FakeTransferSummaryRepository(movimientos),
      conBaseline(),
    );

    expect(find.text('No hay caja abierta en esta terminal.'), findsOneWidget);
    expect(enCard('Saldo estimado'), findsOneWidget);
    expect(enCard(r'$250500.00'), findsOneWidget);
    // Sin efectivo esperado no hay segundo stock que sumar: no hay total.
    expect(find.text('Total en fondos (registrado)'), findsNothing);
    await desarmar(t);
  });

  test('la conciliacion no se persiste ni se convierte en evento', () {
    // Codigo sin comentarios: la guarda busca imports y usos, no prosa.
    final source = File('lib/presentation/pages/caja/saldo_cuenta_estimado_card.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//.*'), '');
    for (final prohibido in const ['drift', 'app_database', 'payload']) {
      expect(
        source.contains(prohibido),
        isFalse,
        reason: 'el bloque de saldo no debe escribir ni emitir ($prohibido)',
      );
    }
    // Ningun evento, commando ni preferencia: la conciliacion vive en memoria.
    for (final prohibido in const ['EventProcessor', 'LocalEventStore', 'events.']) {
      expect(
        source.contains(prohibido),
        isFalse,
        reason: 'no debe emitir ni guardar hechos ($prohibido)',
      );
    }
  });
}