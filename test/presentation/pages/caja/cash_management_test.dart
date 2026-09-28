import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/repositories/cash_repository_impl.dart';
import 'package:pos_flutter/domain/finanzas/financial_category.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_management_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_detail_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_form_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_money.dart';
import 'package:pos_flutter/presentation/pages/finanzas/forms/movimiento_financiero_form_screen.dart';
import '../../../support/cash_harness.dart';
import '../../../support/fake_account_balance_baseline_repository.dart';
import '../../../support/fake_transfer_summary_repository.dart';

void main() {
  Future<void> screen(WidgetTester t, CashHarness h) async {
    t.view.physicalSize = const Size(1280, 1700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: CashManagementScreen(
          repository: CashRepositoryImpl(h.db),
          commands: h.cash,
          // El bloque de transferencias se inyecta vacío: estas pruebas son del
          // corte de caja y no deben depender de la agregación de la Fase 1.
          transfers: FakeTransferSummaryRepository(emptyTransferSummary),
          // Sin saldo inicial declarado: el bloque de saldo queda en aviso y
          // no introduce cifras que confundan al corte.
          baselines: FakeAccountBalanceBaselineRepository(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  test(
    'importes de apertura/conteo permiten cero y mantienen centavos exactos',
    () {
      expect(parseCashMoney('0'), 0);
      expect(parseCashMoney('1.23'), 123);
      expect(parseCashMoney('-1'), isNull);
      expect(parseCashMoney('90071992547409.92'), isNull);
      expect(
        cashMoney(BigInt.parse('27021597764222973')),
        r'$270215977642229.73',
      );
    },
  );
  testWidgets('apertura guarda tras commit y caja actual reacciona', (t) async {
    final h = CashHarness(mode: AppMode.standalone);
    addTearDown(h.dispose);
    await screen(t, h);
    expect(find.text('No hay caja abierta en esta terminal.'), findsOneWidget);
    await t.tap(find.text('Abrir caja'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('cash_amount')), '100.00');
    await t.tap(find.byKey(const Key('cash_save')));
    await t.pumpAndSettle();
    expect(find.text('Caja abierta'), findsOneWidget);
    expect(find.text('Caja abierta.'), findsOneWidget);
    expect(
      (await h.cashStore.current(h.context.deviceId))!.openingMinor,
      10000,
    );
    expect(find.text('Registro local'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets('corte muestra diferencia, historial y detalle inmutable', (
    t,
  ) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    final id = await h.open();
    await h.entry();
    await screen(t, h);
    await t.tap(find.text('Hacer corte'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('cash_amount')), '124.00');
    await t.enterText(find.byKey(const Key('cash_notes')), 'faltante');
    await t.pump();
    expect(find.text(r'Diferencia: -$1.00'), findsOneWidget);
    await t.tap(find.byKey(const Key('cash_save')));
    await t.pumpAndSettle();
    expect((await h.cashStore.find(id))!.status, 'closed');
    await t.tap(find.text('Historial de cortes'));
    await t.pumpAndSettle();
    expect(find.textContaining('Pendiente de aceptación'), findsOneWidget);
    await t.tap(find.byIcon(Icons.chevron_right));
    await t.pumpAndSettle();
    expect(find.text('Caja cerrada'), findsOneWidget);
    expect(find.text('Nota: faltante'), findsOneWidget);
    expect(find.text('Hacer corte'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets(
    'doble toque bloqueado, fallo conserva conteo/nota y permite reintentar',
    (t) async {
      final pending = Completer<void>();
      var calls = 0;
      await t.pumpWidget(
        MaterialApp(
          home: CashFormScreen(
            expectedMinor: BigInt.from(100),
            onSave: (amount, notes) {
              calls++;
              return pending.future;
            },
          ),
        ),
      );
      await t.enterText(find.byKey(const Key('cash_amount')), '0.50');
      await t.enterText(find.byKey(const Key('cash_notes')), 'revisar');
      await t.tap(find.byKey(const Key('cash_save')));
      await t.pump();
      await t.tap(find.byKey(const Key('cash_save')));
      expect(calls, 1);
      pending.completeError(StateError('Fallo de escritura'));
      await t.pumpAndSettle();
      expect(find.text('Fallo de escritura'), findsOneWidget);
      expect(find.text('0.50'), findsOneWidget);
      expect(find.text('revisar'), findsOneWidget);
      expect(find.text('Cerrar caja'), findsOneWidget);
    },
  );
  testWidgets('incidencia de entrega visible sin reabrir corte', (t) async {
    final h = CashHarness();
    addTearDown(h.dispose);
    final id = await h.open();
    final close = await h.cash.cerrar(
      CerrarCajaCommand(sessionId: id, countedMinor: 10000),
    );
    await h.persistence.updateEventSyncStatus(
      close,
      'conflict',
      rejectionReason: 'Dependencia rechazada',
    );
    await t.pumpWidget(
      MaterialApp(
        home: CashDetailScreen(
          sessionId: id,
          repository: CashRepositoryImpl(h.db),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Caja cerrada'), findsOneWidget);
    expect(find.text('Requiere atención'), findsOneWidget);
    expect(find.text('Dependencia rechazada'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets(
    'finanzas selecciona cajón explícitamente y transferencia limpia selección',
    (t) async {
      t.view.physicalSize = const Size(1280, 1200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final category = FinancialCategory(
        id: '11111111-1111-4111-8111-111111111111',
        name: 'Varios',
        direction: FinancialDirection.income,
        nature: FinancialNature.operating,
      );
      await t.pumpWidget(
        MaterialApp(
          home: MovimientoFinancieroFormScreen(
            category: category,
            cashEnabled: true,
            onSave: (result) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      final toggle = find.byKey(const Key('financial_affects_drawer'));
      expect(t.widget<SwitchListTile>(toggle).value, false);
      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(toggle).value, true);
      await t.tap(find.byKey(const Key('movimiento_method')));
      await t.pumpAndSettle();
      await t.tap(find.text('Transferencia').last);
      await t.pumpAndSettle();
      expect(toggle, findsNothing);
      await t.tap(find.byKey(const Key('movimiento_method')));
      await t.pumpAndSettle();
      await t.tap(find.text('Efectivo').last);
      await t.pumpAndSettle();
      expect(t.widget<SwitchListTile>(toggle).value, false);
    },
  );
}
