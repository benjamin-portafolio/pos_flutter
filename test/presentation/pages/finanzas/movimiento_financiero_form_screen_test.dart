import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/finanzas/financial_category.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';
import 'package:pos_flutter/presentation/pages/finanzas/forms/movimiento_financiero_form_screen.dart';
import 'package:pos_flutter/presentation/pages/finanzas/models/movimiento_financiero_form_result.dart';

const _categoria = FinancialCategory(
  id: 'cat-renta',
  name: 'Renta',
  direction: FinancialDirection.expense,
  nature: FinancialNature.operating,
);

/// Host que abre el formulario como la pantalla coordinadora y captura el pop.
class _MovementFormHost extends StatefulWidget {
  const _MovementFormHost({required this.onSave, this.now});

  final Future<void> Function(MovimientoFinancieroFormResult) onSave;
  final DateTime Function()? now;

  @override
  State<_MovementFormHost> createState() => _MovementFormHostState();
}

class _MovementFormHostState extends State<_MovementFormHost> {
  bool? saved;
  bool popped = false;

  Future<void> _open() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MovimientoFinancieroFormScreen(
          category: _categoria,
          now: widget.now,
          onSave: widget.onSave,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      this.saved = saved;
      popped = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: _open, child: const Text('abrir')),
            if (popped) Text(saved == true ? 'SAVED' : 'POPPED'),
          ],
        ),
      ),
    );
  }
}

void main() {
  final now = DateTime(2026, 9, 25, 10, 30);

  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(MovimientoFinancieroFormResult) onSave,
    DateTime Function()? nowProvider,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _MovementFormHost(
          onSave: onSave,
          now: nowProvider ?? () => now,
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('guarda correcto: centavos, método cash, fecha UTC, pop(true)',
      (tester) async {
    final saved = <MovimientoFinancieroFormResult>[];
    await pumpForm(tester, onSave: (r) async => saved.add(r));

    await tester.enterText(find.byKey(const Key('movimiento_importe')), '3500.00');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.amountMinor, 350000);
    expect(saved.single.categoryId, 'cat-renta');
    expect(saved.single.method, 'cash');
    expect(saved.single.occurredAtMs, now.toUtc().millisecondsSinceEpoch);
    expect(saved.single.notes, isNull);
    expect(saved.single.reference, isNull);
    expect(saved.single.entryId, isNotEmpty);
    expect(find.text('SAVED'), findsOneWidget);
  });

  testWidgets('importes inválidos no llaman a onSave', (tester) async {
    var calls = 0;
    await pumpForm(tester, onSave: (_) async => calls++);

    for (final invalido in [
      '0',
      '-5',
      'abc',
      '1.234',
      '9007199254740992',
      '123456789012345.00',
    ]) {
      await tester.enterText(
        find.byKey(const Key('movimiento_importe')),
        invalido,
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(
        find.text('El importe debe ser un entero positivo en centavos.'),
        findsOneWidget,
      );
      expect(calls, 0);
      expect(find.text('POPPED'), findsNothing);
    }
  });

  testWidgets('método transferencia se envía como transfer', (tester) async {
    final saved = <MovimientoFinancieroFormResult>[];
    await pumpForm(tester, onSave: (r) async => saved.add(r));

    await tester.enterText(find.byKey(const Key('movimiento_importe')), '1500');
    await tester.tap(find.byKey(const Key('movimiento_method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transferencia').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(saved.single.method, 'transfer');
    expect(saved.single.amountMinor, 150000);
  });

  testWidgets('nota y referencia opcionales se envían si no están vacías',
      (tester) async {
    final saved = <MovimientoFinancieroFormResult>[];
    await pumpForm(tester, onSave: (r) async => saved.add(r));

    await tester.enterText(find.byKey(const Key('movimiento_importe')), '500.50');
    await tester.enterText(
      find.byKey(const Key('movimiento_nota')),
      'Renta en efectivo',
    );
    await tester.enterText(
      find.byKey(const Key('movimiento_referencia')),
      'REF-2026',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(saved.single.amountMinor, 50050);
    expect(saved.single.notes, 'Renta en efectivo');
    expect(saved.single.reference, 'REF-2026');
  });

  testWidgets('doble toque mientras guarda: un solo onSave y misma identidad',
      (tester) async {
    final gate = Completer<void>();
    final saved = <MovimientoFinancieroFormResult>[];
    await pumpForm(
      tester,
      onSave: (r) async {
        saved.add(r);
        await gate.future;
      },
    );

    await tester.enterText(find.byKey(const Key('movimiento_importe')), '2000');
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Guardando…'), findsOneWidget);
    await tester.tap(find.text('Guardando…'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(saved, hasLength(1));
    // El campo importe queda deshabilitado mientras guarda.
    final field = tester.widget<TextFormField>(
      find.byKey(const Key('movimiento_importe')),
    );
    expect(field.enabled, isFalse);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('SAVED'), findsOneWidget);
    expect(saved, hasLength(1));
    expect(saved.single.amountMinor, 200000);
  });

  testWidgets(
      'error de onSave: SnackBar, conserva el importe y el reintento reutiliza '
      'la misma identidad', (tester) async {
    var calls = 0;
    final saved = <MovimientoFinancieroFormResult>[];
    await pumpForm(
      tester,
      onSave: (r) async {
        calls++;
        if (calls == 1) throw StateError('fallo inyectado');
        saved.add(r);
      },
    );

    await tester.enterText(find.byKey(const Key('movimiento_importe')), '1200.50');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo guardar el registro. Inténtalo nuevamente.'),
      findsOneWidget,
    );
    expect(find.text('1200.50'), findsOneWidget);
    expect(find.text('POPPED'), findsNothing);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.amountMinor, 120050);
    // La misma identidad de intención se reutiliza (idempotencia sin duplicar).
    expect(find.text('SAVED'), findsOneWidget);
  });

  testWidgets('cancelar no registra dinero', (tester) async {
    var calls = 0;
    await pumpForm(tester, onSave: (_) async => calls++);

    await tester.enterText(find.byKey(const Key('movimiento_importe')), '999');
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('SAVED'), findsNothing);
    final host = tester
        .state<_MovementFormHostState>(find.byType(_MovementFormHost));
    expect(host.saved, isNull);
  });

  testWidgets('fecha futura rechazada con el mensaje canónico (reloj hacia atrás)',
      (tester) async {
    var calls = 0;
    // El reloj retrocede 2 h entre que se abre el formulario y se guarda:
    // `occurred_at_ms` (¿hora de apertura) queda > now + 5 min del command.
    var nowMs = now.millisecondsSinceEpoch;
    await pumpForm(
      tester,
      onSave: (_) async => calls++,
      nowProvider: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
    );

    await tester.enterText(find.byKey(const Key('movimiento_importe')), '700');
    nowMs -= 2 * 60 * 60 * 1000;
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('La fecha del registro no puede ser futura.'),
      findsOneWidget,
    );
    expect(calls, 0);
    expect(find.text('POPPED'), findsNothing);
  });
}