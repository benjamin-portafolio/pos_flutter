import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_result.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';

const piece = UnidadInventario(
  id: 'pza',
  code: 'pza',
  nombre: 'Pieza',
  simbolo: 'pza',
  dimension: DimensionUnidad.count,
  factorAtomico: 1,
  maximosDecimales: 0,
  activa: true,
);

void main() {
  final suppliers = ProveedorVariante.canonical([
    ProveedorVariante(
      proveedorId: '00000000-0000-4000-8000-000000000002',
      precioInformadoMenor: 0,
      fechaInformadaMs: 1791331200000,
    ),
  ])!;
  final initial = ArticuloFormVarianteResult.conProveedores(
    id: 'variant',
    nombre: null,
    precioVenta: '25',
    costoEstandar: null,
    proveedores: suppliers,
  );

  testWidgets(
    'editor conserva proveedores al cambiar precio de venta y nombre',
    (tester) async {
      VariantEditorResult? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  saved = await Navigator.of(context).push<VariantEditorResult>(
                    MaterialPageRoute(
                      builder: (_) => VariantEditorScreen(
                        initialValue: initial,
                        canDelete: false,
                        existingNameKeys: const {},
                        inventoryUnit: piece,
                      ),
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('variant_sale_price_field')),
        '30',
      );
      await tester.enterText(
        find.byKey(const Key('variant_name_field')),
        'Grande',
      );
      await tester.tap(find.byKey(const Key('save_variant_button')));
      await tester.pumpAndSettle();
      expect(saved!.value!.proveedores, suppliers);
      expect(saved!.value!.id, initial.id);
      expect(saved!.value!.precioVenta, '30');
    },
  );

  testWidgets('artículo conserva relaciones y fecha al guardar otro nombre', (
    tester,
  ) async {
    ArticuloFormResult? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: ArticleFormScreen(
          categorias: const [],
          unidadesVenta: const [piece],
          initialValue: ArticuloFormResult(
            nombre: 'Café',
            variantes: [initial],
            categoriaId: null,
            saleConfiguration: const UnitSaleConfiguration(),
          ),
          onSave: (value) async => saved = value,
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('article_name_field')),
      'Café nuevo',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();
    expect(saved!.variantes.single.proveedores, suppliers);
    expect(
      saved!.variantes.single.proveedores!.single.fechaInformadaMs,
      1791331200000,
    );
    expect(saved!.variantes.single.id, initial.id);
  });

  test('copyWith conserva por omisión y representa retirada explícita', () {
    expect(initial.copyWith(nombre: 'Grande').proveedores, suppliers);
    expect(
      initial
          .copyWith(recipeComponents: [], clearInventoryUnitId: true)
          .proveedores,
      suppliers,
    );
    final removed = initial.copyWith(proveedores: []);
    expect(removed.proveedores, isEmpty);
    expect(() => removed.proveedores!.clear(), throwsUnsupportedError);
  });
  test('formulario copia proveedores y devuelve una captura inmutable', () {
    final input = List<ProveedorVariante>.of(suppliers);
    final form = ArticuloFormVarianteResult.conProveedores(
      nombre: null,
      precioVenta: '25',
      costoEstandar: null,
      proveedores: input,
    );
    input.clear();
    expect(form.proveedores, suppliers);
    expect(() => form.proveedores!.clear(), throwsUnsupportedError);
  });
}
