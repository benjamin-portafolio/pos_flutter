import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/inventory_resource_filter.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/repositories/recurso_inventario_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';

void main() {
  testWidgets(
    'el check habilita la receta y solo guarda recursos con cantidad',
    (tester) async {
      VariantEditorResult? captured;
      final repository = _FakeInventoryResourceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open_variant_editor'),
                  onPressed: () async {
                    captured = await Navigator.of(context)
                        .push<VariantEditorResult>(
                          MaterialPageRoute(
                            builder: (_) => VariantEditorScreen(
                              initialValue: null,
                              canDelete: false,
                              existingNameKeys: const {},
                              inventoryUnit: _piece,
                              inventoryUnits: const [_piece, _kilogram],
                              inventoryResourceRepository: repository,
                              onCreateInventoryResource: (_) async {},
                            ),
                          ),
                        );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_variant_editor')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('manage_variant_recipe_button')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('variant_recipe_checkbox')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('manage_variant_recipe_button')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('manage_variant_recipe_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recipe_editor_screen')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('add_recipe_inventory_resource_button')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nuevo recurso de inventario'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recipe_editor_screen')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('recipe_quantity_$_flourId')),
        '0.25',
      );
      await tester.tap(find.byKey(const Key('save_recipe_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('variant_recipe_component_$_flourId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('variant_recipe_component_$_waterId')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('variant_sale_price_field')),
        '35',
      );
      await tester.tap(find.byKey(const Key('save_variant_button')));
      await tester.pumpAndSettle();

      expect(captured?.value?.recipeComponents, hasLength(1));
      expect(captured?.value?.recipeComponents.single.resource.id, _flourId);
      expect(captured?.value?.recipeComponents.single.quantity, '0.25');
      expect(captured?.value?.seguimientoExistencias, isFalse);
    },
  );
}

class _FakeInventoryResourceRepository implements RecursoInventarioRepository {
  @override
  Stream<List<RecursoInventarioListado>> watchRecursos({
    String busqueda = '',
    InventoryResourceFilter filtro = InventoryResourceFilter.all,
  }) {
    final normalized = busqueda.trim().toLowerCase();
    return Stream.value(
      _resources
          .where(
            (resource) =>
                normalized.isEmpty ||
                resource.nombre.toLowerCase().contains(normalized),
          )
          .toList(growable: false),
    );
  }
}

const _flourId = '20000000-0000-4000-8000-000000000010';
const _waterId = '20000000-0000-4000-8000-000000000011';

const _piece = UnidadInventario(
  id: '00000000-0000-4000-8000-000000000040',
  code: 'piece',
  nombre: 'Pieza',
  simbolo: 'pza',
  dimension: DimensionUnidad.count,
  factorAtomico: 1,
  maximosDecimales: 0,
  activa: true,
);

const _kilogram = UnidadInventario(
  id: '00000000-0000-4000-8000-000000000041',
  code: 'kg',
  nombre: 'Kilogramo',
  simbolo: 'kg',
  dimension: DimensionUnidad.mass,
  factorAtomico: 1000,
  maximosDecimales: 3,
  activa: true,
);

const _resources = [
  RecursoInventarioListado(
    id: _flourId,
    nombre: 'Harina',
    activo: true,
    existenciaAtomica: 2000,
    unidadPredeterminada: _kilogram,
  ),
  RecursoInventarioListado(
    id: _waterId,
    nombre: 'Agua',
    activo: true,
    existenciaAtomica: 5000,
    unidadPredeterminada: _kilogram,
  ),
];
