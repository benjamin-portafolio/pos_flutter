import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/inventory_categories_tab.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/widgets/inventory_category_card.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';

void main() {
  const categoria = Categoria(
    id: 'category-1',
    nombre: 'Bebidas',
    color: ColorCategoria.blue,
    orden: 0,
  );
  final categoriaRepository = _FakeCategoriaRepository([categoria]);

  testWidgets('shows the three inventory tabs without modifiers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
        ),
      ),
    );

    expect(find.text('ARTÍCULOS'), findsOneWidget);
    expect(find.text('CATEGORÍA'), findsOneWidget);
    expect(find.text('INGREDIENTES'), findsOneWidget);
    expect(find.text('MODIFICADORES'), findsNothing);
  });

  testWidgets('shows categories from the repository and the add button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
        ),
      ),
    );

    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();

    expect(find.byType(InventoryCategoriesTab), findsOneWidget);
    expect(find.byType(InventoryCategoryCard), findsOneWidget);
    expect(find.text('Bebidas'), findsOneWidget);
    expect(find.text('Cerveza'), findsNothing);
    expect(find.byTooltip('Agregar'), findsOneWidget);
  });

  testWidgets('changes tabs by tapping and swiping', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
        ),
      ),
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

class _FakeCategoriaRepository implements CategoriaRepository {
  _FakeCategoriaRepository(this.categorias);

  final List<Categoria> categorias;

  @override
  Future<List<Categoria>> obtenerCategorias() async => categorias;

  @override
  Stream<List<Categoria>> watchCategorias() => Stream.value(categorias);
}
