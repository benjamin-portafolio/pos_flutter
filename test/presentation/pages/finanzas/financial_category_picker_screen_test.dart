import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/finanzas/crear_categoria_financiera_command.dart';
import 'package:pos_flutter/domain/finanzas/financial_category.dart';
import 'package:pos_flutter/domain/finanzas/financial_direction.dart';
import 'package:pos_flutter/domain/finanzas/financial_nature.dart';
import 'package:pos_flutter/presentation/pages/finanzas/selector/financial_category_picker_screen.dart';

import 'support/finanzas_test_harness.dart';

class _PickerHost extends StatefulWidget {
  const _PickerHost({required this.direction, required this.harness});

  final FinancialDirection direction;
  final FinanzasTestHarness harness;

  @override
  State<_PickerHost> createState() => _PickerHostState();
}

class _PickerHostState extends State<_PickerHost> {
  FinancialCategory? selected;

  Future<void> _open() async {
    final selected = await Navigator.of(context).push<FinancialCategory>(
      MaterialPageRoute(
        builder: (_) => FinancialCategoryPickerScreen(
          direction: widget.direction,
          repository: widget.harness.categoryRepository(),
          commandService: widget.harness.categoryCommands(),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => this.selected = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: _open, child: const Text('abrir')),
            if (selected != null) Text('SELECCIONADA:${selected!.name}'),
          ],
        ),
      ),
    );
  }
}

Future<void> _seedCategoria(
  FinanzasTestHarness harness,
  String name, {
  required FinancialDirection direction,
  FinancialNature nature = FinancialNature.operating,
}) async {
  await harness.categoryCommands().crear(
    CrearCategoriaFinancieraCommand(
      categoryId: 'id-${name.toLowerCase().replaceAll(' ', '-')}',
      name: name,
      direction: direction,
      nature: nature,
    ),
  );
}

/// Libera el árbol y drena el timer de cierre que Drift agenda al cancelar la
/// subscripción de un `watch()` (mismo patrón que el test de artículos).
Future<void> _drenarTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  Future<FinanzasTestHarness> createHarness() async {
    final harness = await FinanzasTestHarness.create();
    addTearDown(harness.dispose);
    return harness;
  }

  Future<void> pumpPicker(
    WidgetTester tester,
    FinanzasTestHarness harness, {
    required FinancialDirection direction,
  }) async {
    await tester.pumpWidget(
      MaterialApp(home: _PickerHost(direction: direction, harness: harness)),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra solo las categorías de la dirección y filtra por búsqueda',
      (tester) async {
    final harness = await createHarness();
    await _seedCategoria(harness, 'Renta', direction: FinancialDirection.expense);
    await _seedCategoria(harness, 'Ventas', direction: FinancialDirection.income);
    await _seedCategoria(
      harness,
      'Crédito',
      direction: FinancialDirection.income,
      nature: FinancialNature.capital,
    );

    await pumpPicker(tester, harness, direction: FinancialDirection.income);

    expect(find.byKey(const ValueKey('categoria_id-ventas')), findsOneWidget);
    expect(find.byKey(const ValueKey('categoria_id-crédito')), findsOneWidget);
    expect(find.byKey(const ValueKey('categoria_id-renta')), findsNothing);

    await tester.enterText(find.byKey(const Key('categoria_busqueda')), 'vent');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('categoria_id-ventas')), findsOneWidget);
    expect(find.byKey(const ValueKey('categoria_id-crédito')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('categoria_busqueda')),
      'zzz-inexistente',
    );
    await tester.pumpAndSettle();
    expect(find.text('No hay categorías que coincidan.'), findsOneWidget);
    await _drenarTree(tester);
  });

  testWidgets('búsqueda ignora acentos y mayúsculas', (tester) async {
    final harness = await createHarness();
    await _seedCategoria(harness, 'Cafetería', direction: FinancialDirection.expense);
    await _seedCategoria(harness, 'Renta', direction: FinancialDirection.expense);

    await pumpPicker(tester, harness, direction: FinancialDirection.expense);
    await tester.enterText(
      find.byKey(const Key('categoria_busqueda')),
      'CAFETERIA',
    );
    await tester.pumpAndSettle();

    expect(find.text('Cafetería'), findsOneWidget);
    expect(find.text('Renta'), findsNothing);
    await _drenarTree(tester);
  });

  testWidgets('estado vacío total invita a crear; con otras direcciones avisa',
      (tester) async {
    final harness = await createHarness();

    // Sin ninguna categoría: el estado vacío invita a crear.
    await pumpPicker(tester, harness, direction: FinancialDirection.income);

    expect(find.text('Aún no hay categorías de ingreso.'), findsOneWidget);
    expect(
      find.text('Crea una categoría para poder registrar el movimiento.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('categoria_nueva')), findsOneWidget);
    await _drenarTree(tester);

    // Con categorías de otra dirección: no coincide, sin invitar a crear.
    await _seedCategoria(harness, 'Renta', direction: FinancialDirection.expense);
    await pumpPicker(tester, harness, direction: FinancialDirection.income);
    expect(find.text('No hay categorías que coincidan.'), findsOneWidget);
    expect(
      find.text('Crea una categoría para poder registrar el movimiento.'),
      findsNothing,
    );
    await _drenarTree(tester);
  });

  testWidgets('seleccionar una categoría existente la devuelve', (tester) async {
    final harness = await createHarness();
    await _seedCategoria(harness, 'Renta', direction: FinancialDirection.expense);

    await pumpPicker(tester, harness, direction: FinancialDirection.expense);
    await tester.tap(find.byKey(const ValueKey('categoria_id-renta')));
    await tester.pumpAndSettle();

    expect(find.text('SELECCIONADA:Renta'), findsOneWidget);
    await _drenarTree(tester);
  });

  testWidgets(
      'crear categoría desde el selector: alta real y selección automática '
      'al regresar', (tester) async {
    final harness = await createHarness();
    await pumpPicker(tester, harness, direction: FinancialDirection.income);

    await tester.tap(find.byKey(const Key('categoria_nueva')));
    await tester.pumpAndSettle();
    expect(find.text('Nueva categoría (Ingreso)'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('categoria_nombre')), 'Otros ingresos');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    // El selector se cierra automáticamente con la categoría recién creada.
    expect(find.text('SELECCIONADA:Otros ingresos'), findsOneWidget);

    // Alta real: categoría persistida y evento aplicado (delivery pending).
    final rows = await harness.db.select(harness.db.financialCategories).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Otros ingresos');
    expect(rows.single.direction, 'in');
    final events = await harness.db.select(harness.db.events).get();
    expect(events, hasLength(1));
    expect(events.single.applicationStatus, 'applied');
    expect(events.single.deliveryStatus, 'pending');
    await _drenarTree(tester);
  });
}