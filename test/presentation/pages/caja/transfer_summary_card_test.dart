import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/repositories/cash_repository_impl.dart';
import 'package:pos_flutter/domain/finanzas/transfer_summary.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_form_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_management_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_session_content.dart';
import 'package:pos_flutter/presentation/pages/caja/transfer_summary_card.dart';
import '../../../support/cash_harness.dart';
import '../../../support/fake_account_balance_baseline_repository.dart';
import '../../../support/fake_transfer_summary_repository.dart';

void main() {
  const card = Key('transfer_summary_card');

  Future<void> screen(
    WidgetTester t,
    CashHarness h,
    FakeTransferSummaryRepository transfers, {
    FakeAccountBalanceBaselineRepository? baselines,
    Size size = const Size(1280, 1600),
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
          // Sin saldo inicial declarado: estos tests son del bloque de flujo y
          // el bloque de saldo queda en su estado de aviso, sin sumar nada.
          baselines: baselines ?? FakeAccountBalanceBaselineRepository(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  /// Resumen de la ventana pedida: 10.00 de entrada y 15.00 de salida, neto
  /// -5.00. Cifras distintas a propósito, para que una etiqueta no se confunda
  /// con otra y el neto negativo se vea formateado.
  TransferSummary conMovimiento(int fromMs, int toMs) =>
      TransferSummary.fromMovements(
        fromMs: fromMs,
        toMs: toMs,
        movements: transferMovements(
          entradas: 1,
          salidas: 3,
          occurredAtMs: fromMs,
        ),
      );

  List<String> textos(WidgetTester t) => t
      .widgetList<Text>(
        find.descendant(of: find.byKey(card), matching: find.byType(Text)),
      )
      .map((w) => w.data ?? '')
      .toList();

  /// Codigo sin comentarios: las guardas de source buscan codigo, no prosa.
  /// El comentario que explica H7 nombra `expectedMinor` a proposito.
  String codigo(String path) => File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*'), '');

  testWidgets(
    'el bloque de efectivo no cambia y el de transferencias va aparte',
    (t) async {
      final h = CashHarness();
      addTearDown(h.dispose);
      final id = await h.open(amount: 20000);
      await h.entry(
        direction: 'in',
        method: 'cash',
        drawer: true,
        amount: 3000,
      );
      await screen(t, h, FakeTransferSummaryRepository(conMovimiento));

      // Bloque 1, efectivo: exactamente lo que mostraba antes de esta fase.
      expect(find.byType(CashSessionContent), findsOneWidget);
      expect(find.text('Caja abierta'), findsOneWidget);
      expect(find.text('Terminal: cash-tablet'), findsOneWidget);
      expect(find.text('Fondo inicial'), findsOneWidget);
      expect(find.text('Entradas'), findsOneWidget);
      expect(find.text('Salidas'), findsOneWidget);
      expect(find.text('Efectivo esperado'), findsOneWidget);
      expect(find.text(r'$200.00'), findsOneWidget);
      expect(find.text(r'$30.00'), findsOneWidget);
      expect(find.text(r'$0.00'), findsOneWidget);
      expect(find.text(r'$230.00'), findsOneWidget);
      expect(find.text('1 movimientos'), findsOneWidget);
      expect(
        find.text('Pendiente de sincronizar'),
        findsOneWidget,
        reason: 'el chip de entrega del bloque de efectivo no se toca',
      );

      // Bloque 2, transferencias: presente, con su propio encabezado.
      expect(find.byType(TransferSummaryCard), findsOneWidget);
      expect(
        find.text('Transferencias · movimiento del periodo'),
        findsOneWidget,
      );

      // El corte de caja sigue igual: el botón abre el formulario con el
      // efectivo esperado de antes, sin que el bloque nuevo lo altere.
      await t.tap(find.text('Hacer corte'));
      await t.pumpAndSettle();
      expect(find.byType(CashFormScreen), findsOneWidget);
      expect(find.text('Cerrar caja'), findsOneWidget);
      await t.enterText(find.byKey(const Key('cash_amount')), '230.00');
      await t.tap(find.byKey(const Key('cash_save')));
      await t.pumpAndSettle();
      final cerrada = (await h.cashStore.find(id))!;
      expect(cerrada.status, 'closed');
      expect(cerrada.close!.expectedMinor, '23000');
      expect(cerrada.close!.countedMinor, 23000);
      expect(cerrada.close!.differenceMinor, '0');
      expect(find.text('Corte guardado localmente.'), findsOneWidget);
      // El bloque de transferencias no desaparece al cerrar la caja.
      expect(find.byType(TransferSummaryCard), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'ninguna etiqueta del bloque de transferencias dice total ni saldo',
    (t) async {
      final h = CashHarness();
      addTearDown(h.dispose);
      await h.open();
      await screen(t, h, FakeTransferSummaryRepository(conMovimiento));

      // Las etiquetas de las tres cifras, con nombre propio para no confundirse
      // con las del bloque de efectivo.
      for (final etiqueta in const [
        'Entradas por transferencia',
        'Salidas por transferencia',
        'Neto del periodo',
      ]) {
        expect(find.text(etiqueta), findsOneWidget);
      }
      expect(find.text(r'$10.00'), findsOneWidget);
      expect(find.text(r'$15.00'), findsOneWidget);
      expect(find.text(r'-$5.00'), findsOneWidget);
      expect(
        find.text('4 transferencias registradas en el periodo.'),
        findsOneWidget,
      );

      // Ninguna etiqueta corta del bloque dice "total", "saldo" ni "fondos". El
      // filtro de longitud separa las etiquetas de los textos explicativos, que
      // sí tienen que nombrar el saldo para decir que no se declara.
      final prohibido = RegExp(
        r'total|saldo|fondos|en cuenta|disponible',
        caseSensitive: false,
      );
      for (final texto in textos(t)) {
        if (texto.length > 40) continue;
        expect(
          prohibido.hasMatch(texto),
          isFalse,
          reason: 'la etiqueta "$texto" se lee como un saldo o un total',
        );
      }
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );

  testWidgets('periodo vacio lo dice y no muestra ceros pelados', (t) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    await h.open(amount: 20000);
    await h.entry(direction: 'in', method: 'cash', drawer: true, amount: 3000);
    await screen(t, h, FakeTransferSummaryRepository(emptyTransferSummary));

    expect(
      find.textContaining('Sin transferencias en el periodo'),
      findsOneWidget,
    );
    expect(
      find.textContaining('el saldo de la cuenta se consulta'),
      findsOneWidget,
    );
    // Ninguna cifra dentro del bloque: un cero pelado se lee como saldo.
    for (final etiqueta in const [
      r'$0.00',
      'Neto del periodo',
      'Entradas por transferencia',
      'Salidas por transferencia',
    ]) {
      expect(
        find.descendant(of: find.byKey(card), matching: find.text(etiqueta)),
        findsNothing,
        reason: 'el bloque vacio no muestra "$etiqueta"',
      );
    }
    // El efectivo sigue mostrando lo suyo, incluido su propio cero de salidas.
    expect(find.text('Efectivo esperado'), findsOneWidget);
    expect(find.text(r'$230.00'), findsOneWidget);
    expect(find.text(r'$0.00'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });

  testWidgets('sin saldo inicial declarado no hay ningun total combinado', (
    t,
  ) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    await h.open(amount: 20000);
    await h.entry(direction: 'in', method: 'cash', drawer: true, amount: 3000);
    final transfers = FakeTransferSummaryRepository(conMovimiento);
    await screen(t, h, transfers);

    // Efectivo 230.00, neto de transferencias -5.00. Sin el saldo inicial
    // declarado no hay total en fondos (Fase 4), asi que ninguna combinacion
    // de esas dos cifras puede aparecer en pantalla: ni la suma ni la resta,
    // ni siquiera embebidas en un texto mas largo.
    expect(find.text(r'$230.00'), findsOneWidget);
    expect(find.text(r'-$5.00'), findsOneWidget);
    expect(find.text('Total en fondos (registrado)'), findsNothing);
    for (final combinada in const [
      r'$225.00',
      r'$240.00',
      r'$245.00',
      r'$205.00',
      r'$195.00',
    ]) {
      expect(
        find.textContaining(combinada),
        findsNothing,
        reason: 'total combinado $combinada',
      );
    }

    // El bloque de efectivo no recibe el agregado bancario y el bloque de
    // transferencias no recibe la cifra de caja: ninguna de las dos partes
    // tiene los dos numeros, asi que sumar es imposible en esos archivos. El
    // total combinado solo puede vivir en el bloque de saldo en cuenta, que es
    // donde conviven el estimado y el efectivo esperado.
    final cardSource = codigo(
      'lib/presentation/pages/caja/transfer_summary_card.dart',
    );
    for (final efectivo in const [
      'expectedMinor',
      'openingMinor',
      'countedMinor',
      'differenceMinor',
    ]) {
      expect(
        cardSource.contains(efectivo),
        isFalse,
        reason: 'el bloque de transferencias no debe leer $efectivo',
      );
    }
    final screenSource = codigo(
      'lib/presentation/pages/caja/cash_management_screen.dart',
    );
    for (final bancario in const ['netMinor', 'incomeMinor', 'expenseMinor']) {
      expect(
        screenSource.contains(bancario),
        isFalse,
        reason: 'la pantalla no debe calcular con $bancario',
      );
    }
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });

  testWidgets('el periodo por defecto es el turno y el selector cambia a hoy', (
    t,
  ) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    await h.open();
    final transfers = FakeTransferSummaryRepository(conMovimiento);
    await screen(t, h, transfers);

    // Con caja abierta el default es el turno, cuya ventana arranca en la
    // apertura de la sesion: es la misma ventana que usa el corte de caja.
    final session = (await h.cashStore.current(h.context.deviceId))!;
    expect(transfers.windows.first.fromMs, session.openedAtMs);

    await t.tap(find.text('Hoy'));
    await t.pumpAndSettle();
    expect(transfers.windows.length, 2);
    final hoy = transfers.windows.last;
    final inicio = DateTime.fromMillisecondsSinceEpoch(hoy.fromMs);
    expect(
      DateTime(inicio.year, inicio.month, inicio.day),
      inicio,
      reason: 'el dia arranca a medianoche local',
    );
    expect(hoy.toMs, greaterThan(hoy.fromMs));
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });

  testWidgets('un fallo de consulta se dice y no tapa el bloque de efectivo', (
    t,
  ) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    await h.open(amount: 20000);
    await screen(
      t,
      h,
      FakeTransferSummaryRepository(emptyTransferSummary, falla: true),
    );

    expect(
      find.textContaining('No se pudo consultar el movimiento'),
      findsOneWidget,
    );
    // No queda un spinner girando: no sabemos nada y hay que decirlo.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // El efectivo sigue intacto.
    expect(find.text('Efectivo esperado'), findsOneWidget);
    expect(find.text(r'$200.00'), findsNWidgets(2));
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });

  testWidgets('sin caja abierta el bloque no ofrece turno y cae al dia', (
    t,
  ) async {
    final h = CashHarness(mode: AppMode.standalone);
    addTearDown(h.dispose);
    final transfers = FakeTransferSummaryRepository(conMovimiento);
    await screen(t, h, transfers);

    expect(find.text('No hay caja abierta en esta terminal.'), findsOneWidget);
    expect(find.byType(TransferSummaryCard), findsOneWidget);
    expect(find.text('Turno actual'), findsNothing);
    expect(find.text('Hoy'), findsOneWidget);
    final hoy = transfers.windows.first;
    expect(hoy.toMs, greaterThan(hoy.fromMs));
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
}
