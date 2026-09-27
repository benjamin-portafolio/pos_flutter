import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/finanzas/crear_categoria_financiera_command.dart';
import 'package:pos_flutter/application/commands/finanzas/registrar_movimiento_financiero_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';
import 'package:pos_flutter/presentation/pages/finanzas/ingresos_y_gastos_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import 'package:uuid/uuid.dart';

import 'support/finanzas_test_harness.dart';

// «Hoy» de la prueba: 7 días atrás del reloj real, garantizando que
// `occurred_at_ms` nunca caiga en el futuro que el command rechaza
// (contrato §2.4: `now + 5 min`). La pantalla arranca en el período de ese día
// y los movimientos sembrados caen dentro de él.
final _now = DateTime.now().subtract(const Duration(days: 7));
final _hoyLabel = ReportPeriod.formatDate(_now);
final _ayerLabel = ReportPeriod.formatDate(_now.subtract(const Duration(days: 1)));

/// Sembra categoría + movimiento por los command services reales y devuelve el
/// `eventId` del movimiento (para forzar incidencias de entrega). El command
/// exige `entry_id` UUID v4 (sobre duplicados idempotentes).
Future<String> _seedMovimiento(
  FinanzasTestHarness harness, {
  required String categoryId,
  required String categoryName,
  required FinancialDirection direction,
  required int amountMinor,
  required String method,
  DateTime? fecha,
  String? notes,
  String? reference,
}) async {
  await harness.categoryCommands().crear(
    CrearCategoriaFinancieraCommand(
      categoryId: categoryId,
      name: categoryName,
      direction: direction,
      nature: FinancialNature.operating,
    ),
  );
  return harness.movementCommands().registrar(
    RegistrarMovimientoFinancieroCommand(
      entryId: const Uuid().v4(),
      categoryId: categoryId,
      amountMinor: amountMinor,
      method: method,
      occurredAtMs: (fecha ?? _now).toUtc().millisecondsSinceEpoch,
      notes: notes,
      reference: reference,
    ),
  );
}

Future<void> _pumpScreen(WidgetTester tester, FinanzasTestHarness harness) async {
  // Superficie alta para que la lista completa (resumen + filtro + tarjetas con
  // chip) quede dentro del viewport y las tarjetas no queden bajo el fold.
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: IngresosYGastosScreen(
        entryRepository: harness.entryRepository(),
        categoryRepository: harness.categoryRepository(),
        categoryCommandService: harness.categoryCommands(),
        movementCommandService: harness.movementCommands(),
        now: () => _now,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Libera el árbol y drena el timer de cierre que Drift agenda al cancelar las
/// subscripciones de los `watch()` (mismo patrón que el test de artículos).
Future<void> _drenarTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  Future<FinanzasTestHarness> createHarness({AppMode mode = AppMode.serverSync}) async {
    final harness = await FinanzasTestHarness.create(mode: mode);
    addTearDown(harness.dispose);
    return harness;
  }

  testWidgets('estado vacío: período de hoy, totales en cero y aviso',
      (tester) async {
    final harness = await createHarness();
    await _pumpScreen(tester, harness);

    expect(find.text(_hoyLabel), findsOneWidget);
    expect(find.text(r'$0.00 MXN'), findsWidgets);
    expect(find.text('Neto de registros adicionales'), findsOneWidget);
    expect(
      find.textContaining('Sin registros adicionales en este período.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No son utilidad ni saldo de caja.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('boton_ingreso')), findsOneWidget);
    expect(find.byKey(const Key('boton_gasto')), findsOneWidget);
    await _drenarTree(tester);
  });

  testWidgets(
      'flujo completo de ingreso: crear categoría desde el selector, registrar, '
      'y lista/totales reactivos', (tester) async {
    final harness = await createHarness();
    await _pumpScreen(tester, harness);

    await tester.tap(find.byKey(const Key('boton_ingreso')));
    await tester.pumpAndSettle();
    expect(find.text('Aún no hay categorías de ingreso.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('categoria_nueva')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('categoria_nombre')), 'Otros ingresos');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    // El flujo continúa directo al formulario del movimiento con esa categoría.
    expect(find.text('Registrar ingreso'), findsOneWidget);
    expect(find.text('Otros ingresos'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('movimiento_importe')), '2500.00');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ingreso registrado y guardado. La lista se actualizó.'),
      findsOneWidget,
    );
    // Lista reactiva: tarjeta nueva + totales del resumen con el mismo importe
    // (Ingresos, Efectivo, Neto y la tarjeta).
    expect(find.text('Otros ingresos'), findsOneWidget);
    expect(find.text(r'$2500.00 MXN'), findsNWidgets(4));
    // Incidencia/canal: en serverSync el evento queda pendiente.
    expect(find.text('Pendiente de sincronizar'), findsOneWidget);

    // Persistencia real: categoría, registro y evento aplicado.
    expect(await harness.db.select(harness.db.financialCategories).get(), hasLength(1));
    final entries = await harness.db.select(harness.db.financialEntries).get();
    expect(entries, hasLength(1));
    expect(entries.single.amountMinor, 250000);
    final events = await harness.db.select(harness.db.events).get();
    expect(events, hasLength(2));
    expect(events.every((e) => e.applicationStatus == 'applied'), isTrue);
    expect(events.every((e) => e.deliveryStatus == 'pending'), isTrue);

    // Deja que el SnackBar se cierre y drena los timers de Drift.
    await tester.pump(const Duration(seconds: 5));
    await _drenarTree(tester);
  });

  testWidgets('flujo de gasto con categoría existente', (tester) async {
    final harness = await createHarness();
    await harness.categoryCommands().crear(
      const CrearCategoriaFinancieraCommand(
        categoryId: 'a6666666-6666-4666-8666-666666666666',
        name: 'Renta',
        direction: FinancialDirection.expense,
        nature: FinancialNature.operating,
      ),
    );
    await _pumpScreen(tester, harness);

    await tester.tap(find.byKey(const Key('boton_gasto')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('categoria_a6666666-6666-4666-8666-666666666666')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Registrar gasto'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('movimiento_importe')), '1500.00');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('Gasto registrado y guardado. La lista se actualizó.'),
      findsOneWidget,
    );
    expect(find.text('Renta'), findsOneWidget);
    // Gastos, Efectivo y la tarjeta; el neto es negativo (-$1500.00 MXN).
    expect(find.text(r'$1500.00 MXN'), findsNWidgets(3));
    expect(find.text(r'-$1500.00 MXN'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await _drenarTree(tester);
  });

  testWidgets('modo standalone: chip de registro local y sin refs de sync',
      (tester) async {
    final harness = await createHarness(mode: AppMode.standalone);

    await _seedMovimiento(
      harness,
      categoryId: 'a1111111-1111-4111-8111-111111111111',
      categoryName: 'Solo local',
      direction: FinancialDirection.income,
      amountMinor: 10000,
      method: 'cash',
    );
    await _pumpScreen(tester, harness);

    expect(find.text('Solo local'), findsOneWidget);
    expect(find.text('Registro local'), findsOneWidget);
    expect(find.text('Pendiente de sincronizar'), findsNothing);
    expect(await harness.db.select(harness.db.eventRefs).get(), isEmpty);
    await _drenarTree(tester);
  });

  testWidgets(
      'incidencia de entrega: chip de atención y motivo en el detalle sin '
      'ocultar el monto', (tester) async {
    final harness = await createHarness();
    final eventId = await _seedMovimiento(
      harness,
      categoryId: 'a2222222-2222-4222-8222-222222222222',
      categoryName: 'Venta rechazada',
      direction: FinancialDirection.income,
      amountMinor: 80000,
      method: 'cash',
    );
    await harness.persistence().updateEventSyncStatus(
      eventId,
      'rejected',
      rejectionReason: 'El servidor rechazó el registro.',
    );
    await _pumpScreen(tester, harness);

    expect(find.text('Venta rechazada'), findsOneWidget);
    // Ingresos, Efectivo, Neto y la tarjeta.
    expect(find.text(r'$800.00 MXN'), findsNWidgets(4));
    expect(find.text('Requiere atención'), findsOneWidget);

    await tester.tap(find.text('Venta rechazada'));
    await tester.pumpAndSettle();

    expect(find.text('Detalle del registro'), findsOneWidget);
    expect(find.text('El servidor rechazó el registro.'), findsOneWidget);
    expect(find.text('Trazabilidad'), findsOneWidget);
    // Headline + fila "Monto" (SelectableText) en el detalle.
    expect(find.text(r'$800.00 MXN'), findsNWidgets(2));
    // El chip del detalle y la fila "Entrega" etiquetan la incidencia.
    expect(find.text('Requiere atención'), findsNWidgets(2));
    await _drenarTree(tester);
  });

  testWidgets('filtro por método actualiza la lista y los totales',
      (tester) async {
    final harness = await createHarness();
    await _seedMovimiento(
      harness,
      categoryId: 'a3333333-3333-4333-8333-333333333333',
      categoryName: 'Ventas de mostrador',
      direction: FinancialDirection.income,
      amountMinor: 50000,
      method: 'cash',
    );
    await _seedMovimiento(
      harness,
      categoryId: 'a4444444-4444-4444-8444-444444444444',
      categoryName: 'Transferencia recibida',
      direction: FinancialDirection.income,
      amountMinor: 150000,
      method: 'transfer',
    );
    await _pumpScreen(tester, harness);

    expect(find.text('Ventas de mostrador'), findsOneWidget);
    expect(find.text('Transferencia recibida'), findsOneWidget);

    // Solo transferencia.
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<String?>),
        matching: find.text('Transferencia'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ventas de mostrador'), findsNothing);
    expect(find.text('Transferencia recibida'), findsOneWidget);
    // Ingresos, Transferencia, Neto y la tarjeta.
    expect(find.text(r'$1500.00 MXN'), findsNWidgets(4));
    expect(find.text(r'$500.00 MXN'), findsNothing);

    // Solo efectivo.
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<String?>),
        matching: find.text('Efectivo'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ventas de mostrador'), findsOneWidget);
    expect(find.text('Transferencia recibida'), findsNothing);
    expect(find.text(r'$500.00 MXN'), findsNWidgets(4));

    // Todos de nuevo.
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<String?>),
        matching: find.text('Todos'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ventas de mostrador'), findsOneWidget);
    expect(find.text('Transferencia recibida'), findsOneWidget);
    await _drenarTree(tester);
  });

  testWidgets('período: flechas cambian el día y el reporte reacciona',
      (tester) async {
    final harness = await createHarness();
    await _seedMovimiento(
      harness,
      categoryId: 'a5555555-5555-4555-8555-555555555555',
      categoryName: 'Registro de hoy',
      direction: FinancialDirection.income,
      amountMinor: 2000,
      method: 'cash',
    );
    await _pumpScreen(tester, harness);

    expect(find.text(_hoyLabel), findsOneWidget);
    expect(find.text('Registro de hoy'), findsOneWidget);

    await tester.tap(find.byTooltip('Período anterior'));
    await tester.pumpAndSettle();
    expect(find.text(_ayerLabel), findsOneWidget);
    expect(
      find.textContaining('Sin registros adicionales en este período.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Período siguiente'));
    await tester.pumpAndSettle();
    expect(find.text(_hoyLabel), findsOneWidget);
    expect(find.text('Registro de hoy'), findsOneWidget);
    await _drenarTree(tester);
  });
}