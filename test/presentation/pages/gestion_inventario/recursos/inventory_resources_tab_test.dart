import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/inventario/inventory_resource_filter.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/domain/repositories/recurso_inventario_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/recursos/inventory_resources_tab.dart';

void main() {
  testWidgets('muestra los filtros disponibles y deshabilita ingredientes', (
    tester,
  ) async {
    final repository = _FakeInventoryResourceRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InventoryResourcesTab(repository: repository)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Todos'), findsOneWidget);
    expect(find.text('Productos'), findsOneWidget);
    expect(find.text('Independientes'), findsOneWidget);
    expect(find.text('Ingredientes · Próximamente'), findsOneWidget);
    expect(find.text('Con existencia'), findsOneWidget);
    expect(find.text('Sin existencia'), findsOneWidget);
    expect(find.text('Inactivos'), findsNothing);

    final ingredientsChip = tester.widget<ChoiceChip>(
      find.byKey(const Key('inventory_filter_ingredients')),
    );
    expect(ingredientsChip.onSelected, isNull);

    await tester.tap(find.text('Productos'));
    await tester.pumpAndSettle();

    expect(repository.requestedFilters.last, InventoryResourceFilter.products);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const Key('inventory_filter_products')),
          )
          .selected,
      isTrue,
    );
  });
}

class _FakeInventoryResourceRepository implements RecursoInventarioRepository {
  final requestedFilters = <InventoryResourceFilter>[];

  @override
  Stream<List<RecursoInventarioListado>> watchRecursos({
    String busqueda = '',
    InventoryResourceFilter filtro = InventoryResourceFilter.all,
  }) {
    requestedFilters.add(filtro);
    return Stream.value(const []);
  }
}
