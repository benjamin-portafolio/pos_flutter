import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/widgets/inventory_category_card.dart';

void main() {
  testWidgets('papelera elimina sin disparar edición', (tester) async {
    var edits = 0;
    var deletes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoryCard(
            name: 'Bebidas',
            color: Colors.cyan,
            onTap: () => edits++,
            onMoveUp: null,
            onMoveDown: null,
            onDeleteCategory: () => deletes++,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('delete_category_button')));
    expect(deletes, 1);
    expect(edits, 0);

    await tester.tap(find.text('Bebidas'));
    expect(edits, 1);
  });

  testWidgets('muestra el margen promedio con un decimal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoryCard(
            name: 'Bebidas',
            color: Colors.cyan,
            margenPromedioPorcentaje: 32.456,
            onTap: () {},
            onMoveUp: null,
            onMoveDown: null,
            onDeleteCategory: () {},
          ),
        ),
      ),
    );

    expect(find.text('Margen promedio: 32.5 %'), findsOneWidget);
  });

  testWidgets('sin datos no muestra cero por ciento', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoryCard(
            name: 'Sin productos',
            color: Colors.cyan,
            onTap: () {},
            onMoveUp: null,
            onMoveDown: null,
            onDeleteCategory: () {},
          ),
        ),
      ),
    );

    expect(find.text('Margen promedio: Sin datos'), findsOneWidget);
    expect(find.text('Margen promedio: 0.0 %'), findsNothing);
  });

  testWidgets('distingue carga y error sin valores ficticios', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoryCard(
            name: 'Cargando',
            color: Colors.cyan,
            margenCargando: true,
            onTap: () {},
            onMoveUp: null,
            onMoveDown: null,
            onDeleteCategory: () {},
          ),
        ),
      ),
    );
    expect(find.text('Margen promedio: Cargando...'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoryCard(
            name: 'Con error',
            color: Colors.cyan,
            margenError: true,
            onTap: () {},
            onMoveUp: null,
            onMoveDown: null,
            onDeleteCategory: () {},
          ),
        ),
      ),
    );
    expect(find.text('Margen promedio: No disponible'), findsOneWidget);
  });

  testWidgets('adapta nombre largo y texto escalado sin perder acciones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var edits = 0;
    var deletes = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: InventoryCategoryCard(
              name: 'Categoría con un nombre extraordinariamente largo',
              color: Colors.cyan,
              margenPromedioPorcentaje: 32.5,
              onTap: () => edits++,
              onMoveUp: () {},
              onMoveDown: () {},
              onDeleteCategory: () => deletes++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Margen promedio: 32.5 %'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('delete_category_button')));
    expect(deletes, 1);
    expect(edits, 0);
  });
}
