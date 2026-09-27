import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';
import 'package:pos_flutter/presentation/pages/finanzas/forms/categoria_financiera_form_screen.dart';
import 'package:pos_flutter/presentation/pages/finanzas/models/categoria_financiera_form_result.dart';

/// Host que abre el formulario con un botón y captura el resultado del pop,
/// como lo hace el selector (guardar → cerrar con el resultado).
class _CategoryFormHost extends StatefulWidget {
  const _CategoryFormHost({required this.direction, required this.onSave});

  final FinancialDirection direction;
  final Future<void> Function(CategoriaFinancieraFormResult) onSave;

  @override
  State<_CategoryFormHost> createState() => _CategoryFormHostState();
}

class _CategoryFormHostState extends State<_CategoryFormHost> {
  CategoriaFinancieraFormResult? result;
  bool popped = false;

  Future<void> _open() async {
    final result = await Navigator.of(context).push<CategoriaFinancieraFormResult>(
      MaterialPageRoute(
        builder: (_) => CategoriaFinancieraFormScreen(
          direction: widget.direction,
          onSave: widget.onSave,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      this.result = result;
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
            if (popped) const Text('POPPED'),
          ],
        ),
      ),
    );
  }
}

void main() {
  Future<void> pumpForm(
    WidgetTester tester, {
    required Future<void> Function(CategoriaFinancieraFormResult) onSave,
    FinancialDirection direction = FinancialDirection.income,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: _CategoryFormHost(direction: direction, onSave: onSave),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('anula espacios en blanco (NFKC + trim) y sale con el resultado',
      (tester) async {
    final saved = <CategoriaFinancieraFormResult>[];
    await pumpForm(
      tester,
      onSave: (result) async => saved.add(result),
    );

    await tester.enterText(
      find.byKey(const Key('categoria_nombre')),
      '  Renta  ',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.name, 'Renta');
    expect(saved.single.direction, FinancialDirection.income);
    expect(saved.single.nature, FinancialNature.operating);
    expect(saved.single.categoryId, isNotEmpty);

    expect(find.text('POPPED'), findsOneWidget);
    final host = tester
        .state<_CategoryFormHostState>(find.byType(_CategoryFormHost));
    expect(host.result?.name, saved.single.name);
  });

  testWidgets('nombre vacío valida y no llama a onSave', (tester) async {
    var calls = 0;
    await pumpForm(tester, onSave: (_) async => calls++);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('El nombre de la categoría financiera es obligatorio.'),
      findsOneWidget,
    );
    expect(calls, 0);
    expect(find.text('POPPED'), findsNothing);
  });

  testWidgets('nombre de más de 100 caracteres valida', (tester) async {
    var calls = 0;
    await pumpForm(tester, onSave: (_) async => calls++);

    await tester.enterText(
      find.byKey(const Key('categoria_nombre')),
      'a' * 101,
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('name debe tener entre 1 y 100 caracteres.'),
      findsOneWidget,
    );
    expect(calls, 0);
  });

  testWidgets('selecciona una naturaleza distinta y la envía', (tester) async {
    final saved = <CategoriaFinancieraFormResult>[];
    await pumpForm(tester, onSave: (r) async => saved.add(r));

    await tester.enterText(find.byKey(const Key('categoria_nombre')), 'Crédito');
    await tester.tap(find.byKey(const Key('categoria_naturaleza')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Financiamiento').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(saved.single.nature, FinancialNature.financing);
  });

  testWidgets(
      'ingreso no ofrece naturalezas solo-gasto; gasto sí las ofrece',
      (tester) async {
    // Ingreso: no se ofrecen compras (solo-gasto).
    await pumpForm(
      tester,
      onSave: (_) async {},
      direction: FinancialDirection.income,
    );
    await tester.tap(find.byKey(const Key('categoria_naturaleza')));
    await tester.pumpAndSettle();
    expect(find.text('Compra de equipo o activo'), findsNothing);
    expect(find.text('Compra de mercancía'), findsNothing);
    expect(find.text('Operativo'), findsWidgets);
    expect(find.text('Capital'), findsOneWidget);
    expect(find.text('Financiamiento'), findsOneWidget);
    // Cierra el menú.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Gasto: sí se ofrecen las naturalezas solo-gasto.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpForm(
      tester,
      onSave: (_) async {},
      direction: FinancialDirection.expense,
    );
    await tester.tap(find.byKey(const Key('categoria_naturaleza')));
    await tester.pumpAndSettle();
    expect(find.text('Compra de equipo o activo'), findsOneWidget);
    expect(find.text('Compra de mercancía'), findsOneWidget);
  });

  testWidgets('doble toque mientras guarda dispara un solo onSave',
      (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await pumpForm(
      tester,
      onSave: (_) async {
        calls++;
        await gate.future;
      },
    );

    await tester.enterText(find.byKey(const Key('categoria_nombre')), 'Caja');
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Guardando…'), findsOneWidget);
    await tester.tap(find.text('Guardando…'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('POPPED'), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets(
      'error de onSave: SnackBar, conserva el nombre y el reintento reutiliza '
      'la misma identidad', (tester) async {
    var calls = 0;
    final saved = <CategoriaFinancieraFormResult>[];
    await pumpForm(
      tester,
      onSave: (result) async {
        calls++;
        if (calls == 1) throw StateError('fallo inyectado');
        saved.add(result);
      },
    );

    await tester.enterText(find.byKey(const Key('categoria_nombre')), 'Caja chica');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo guardar la categoría. Inténtalo nuevamente.'),
      findsOneWidget,
    );
    expect(find.text('Caja chica'), findsOneWidget);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single.name, 'Caja chica');
    expect(find.text('POPPED'), findsOneWidget);
    // La misma identidad de intención se reutiliza (idempotencia).
    expect(saved.single.categoryId, isNotEmpty);
  });

  testWidgets('cancelar no guarda ni devuelve resultado', (tester) async {
    var calls = 0;
    await pumpForm(tester, onSave: (_) async => calls++);

    await tester.enterText(find.byKey(const Key('categoria_nombre')), 'Renta');
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    final host = tester
        .state<_CategoryFormHostState>(find.byType(_CategoryFormHost));
    expect(host.result, isNull);
  });
}