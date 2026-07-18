import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/inventory_categories_tab.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/widgets/inventory_category_card.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';

void main() {
  testWidgets('shows the three inventory tabs without modifiers', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: InventoryManagementScreen()),
    );

    expect(find.text('ARTÍCULOS'), findsOneWidget);
    expect(find.text('CATEGORÍA'), findsOneWidget);
    expect(find.text('INGREDIENTES'), findsOneWidget);
    expect(find.text('MODIFICADORES'), findsNothing);
  });

  testWidgets('shows mock categories and the add button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InventoryManagementScreen()),
    );

    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();

    expect(find.byType(InventoryCategoriesTab), findsOneWidget);
    expect(find.byType(InventoryCategoryCard), findsWidgets);
    expect(find.text('Bebidas'), findsOneWidget);
    expect(find.text('Pescados Y Mariscos'), findsOneWidget);
    expect(find.text('Cerveza'), findsOneWidget);
    expect(find.text('Festival'), findsOneWidget);
    expect(find.text('Souvenirs'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Maquila'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('inventory_categories_tab_view')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Maquila'), findsOneWidget);
    expect(find.byTooltip('Agregar'), findsOneWidget);
  });

  testWidgets('changes tabs by tapping and swiping', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: InventoryManagementScreen()),
    );

    final scaffold = find.descendant(
      of: find.byType(InventoryManagementScreen),
      matching: find.byType(Scaffold),
    );
    final controller = DefaultTabController.of(tester.element(scaffold));

    expect(controller.index, 0);

    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();

    expect(controller.index, 1);

    await tester.fling(find.byType(TabBarView), const Offset(-500, 0), 1000);
    await tester.pumpAndSettle();

    expect(controller.index, 2);
  });
}
