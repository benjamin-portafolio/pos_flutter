import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/recurso_inventario_listado.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/inventory_article_card.dart';

void main() {
  testWidgets(
    'muestra un botón seleccionable incluso con una variante sin nombre',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InventoryArticleCard(articulo: _withoutCategory),
          ),
        ),
      );

      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
      expect(find.text('Café americano'), findsOneWidget);
      expect(find.text(r'$45.50'), findsOneWidget);
      expect(find.text('Sin categoría'), findsNothing);
      expect(find.text('< 45.50 >'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.text('< 45.50 >'));
      await tester.pump();
      expect(find.text('Café americano'), findsOneWidget);
      expect(
        find.bySemanticsLabel(r'Café americano, sin categoría, $45.50'),
        findsOneWidget,
      );
    },
  );

  testWidgets('muestra nombre y color de la categoría', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InventoryArticleCard(articulo: _withCategory)),
      ),
    );

    expect(find.text('Té verde'), findsOneWidget);
    expect(find.text('Bebidas'), findsOneWidget);
    expect(find.text(r'$32.00'), findsOneWidget);
    expect(find.bySemanticsLabel('Categoría Bebidas'), findsOneWidget);
  });

  testWidgets(
    'selecciona por orden y actualiza nombre y precio sin abrir detalle',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryArticleCard(
              articulo: _withNamedVariants,
              onTap: () => opened++,
            ),
          ),
        ),
      );

      final buttons = tester
          .widgetList<FilledButton>(find.byType(FilledButton))
          .toList();
      expect(buttons.map((button) => (button.child as Text).data), [
        'Chica',
        'Grande',
        '< 15.00 >',
      ]);
      expect(find.text('Refresco Chica'), findsOneWidget);
      expect(find.text(r'$20.00'), findsOneWidget);
      expect(
        find.bySemanticsLabel(r'Refresco Chica, sin categoría, $20.00'),
        findsOneWidget,
      );
      final context = tester.element(find.byType(InventoryArticleCard));
      final selectedColor = Theme.of(context).colorScheme.primary;
      expect(buttons.first.style!.backgroundColor!.resolve({}), selectedColor);

      await tester.tap(find.text('Grande'));
      await tester.pump();
      expect(find.text('Refresco Grande'), findsOneWidget);
      expect(find.text(r'$30.00'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('article_variant_variant-large')),
            )
            .style!
            .backgroundColor!
            .resolve({}),
        selectedColor,
      );
      expect(opened, 0);

      await tester.tap(find.text('< 15.00 >'));
      await tester.pump();
      expect(find.text('Refresco'), findsOneWidget);
      expect(find.text(r'$15.00'), findsOneWidget);
      expect(find.text(r'$15.00 – $30.00'), findsNothing);
      expect(opened, 0);
    },
  );

  testWidgets('variantes con el mismo precio muestran un solo importe', (
    tester,
  ) async {
    const article = ArticuloListado(
      productoId: 'same-price',
      nombre: 'Café',
      activo: true,
      categoriaId: null,
      categoriaNombre: null,
      categoriaColor: null,
      variantesActivas: [
        VarianteListado(
          varianteId: 'v1',
          nombre: 'A',
          precioVentaMenor: 2000,
          orden: 0,
        ),
        VarianteListado(
          varianteId: 'v2',
          nombre: 'B',
          precioVentaMenor: 2000,
          orden: 1,
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InventoryArticleCard(articulo: article)),
      ),
    );
    expect(find.text(r'$20.00'), findsOneWidget);
    expect(
      find.bySemanticsLabel(r'Café A, sin categoría, $20.00'),
      findsOneWidget,
    );
  });

  testWidgets('abre el detalle al tocar la tarjeta sin usar imágenes', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryArticleCard(
            articulo: _withoutCategory,
            onTap: () => opened++,
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('Café americano'));
    expect(opened, 1);
  });

  testWidgets('admite texto ampliado sin desbordar la tarjeta', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: InventoryArticleCard(articulo: _withNamedVariants),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Refresco Chica'), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(3));
  });

  testWidgets(
    'muestra saldo por variante, incluido cero, y oculta falta de seguimiento',
    (tester) async {
      await _pumpArticle(tester, _stockArticle());
      expect(find.text('2.5 kg en existencia'), findsOneWidget);
      expect(find.text(r'$154.00 x 1 kg'), findsOneWidget);
      expect(find.text('< 154.00 >'), findsOneWidget);

      await tester.tap(find.text('Vacía'));
      await tester.pump();
      expect(find.text('0 kg en existencia'), findsOneWidget);
      expect(find.text('2.5 kg en existencia'), findsNothing);
      expect(find.text(r'$100.00 x 1 kg'), findsOneWidget);

      await tester.tap(find.text('Sin seguimiento'));
      await tester.pump();
      expect(find.textContaining('en existencia'), findsNothing);
      expect(find.text(r'$80.00 x 1 kg'), findsOneWidget);
    },
  );

  testWidgets(
    'conserva selección al actualizar saldo y vuelve a la primera si se retira',
    (tester) async {
      await _pumpArticle(tester, _stockArticle());
      await tester.tap(find.text('Vacía'));
      await tester.pump();
      await _pumpArticle(tester, _stockArticle(secondBalance: 1250));
      expect(find.text('Harina Vacía'), findsOneWidget);
      expect(find.text('1.25 kg en existencia'), findsOneWidget);

      await _pumpArticle(tester, _stockArticle(removeSecond: true));
      expect(find.text('Harina'), findsOneWidget);
      expect(find.text('2.5 kg en existencia'), findsOneWidget);
    },
  );

  testWidgets(
    'texto ampliado admite unidad, saldo y nombres largos en pantalla estrecha',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: InventoryArticleCard(articulo: _stockArticle()),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text(r'$154.00 x 1 kg'), findsOneWidget);
      expect(find.text('2.5 kg en existencia'), findsOneWidget);
    },
  );
}

const _withoutCategory = ArticuloListado(
  productoId: 'product-coffee',
  nombre: 'Café americano',
  activo: true,
  categoriaId: null,
  categoriaNombre: null,
  categoriaColor: null,
  variantesActivas: [
    VarianteListado(
      varianteId: 'variant-coffee',
      nombre: null,
      precioVentaMenor: 4550,
      orden: 0,
    ),
  ],
);

const _withCategory = ArticuloListado(
  productoId: 'product-tea',
  nombre: 'Té verde',
  activo: true,
  categoriaId: 'category-drinks',
  categoriaNombre: 'Bebidas',
  categoriaColor: ColorCategoria.green,
  variantesActivas: [
    VarianteListado(
      varianteId: 'variant-tea',
      nombre: null,
      precioVentaMenor: 3200,
      orden: 0,
    ),
  ],
);

const _withNamedVariants = ArticuloListado(
  productoId: 'product-named',
  nombre: 'Refresco',
  activo: true,
  categoriaId: null,
  categoriaNombre: null,
  categoriaColor: null,
  variantesActivas: [
    VarianteListado(
      varianteId: 'variant-large',
      nombre: 'Grande',
      precioVentaMenor: 3000,
      orden: 1,
    ),
    VarianteListado(
      varianteId: 'variant-simple',
      nombre: null,
      precioVentaMenor: 1500,
      orden: 2,
    ),
    VarianteListado(
      varianteId: 'variant-small',
      nombre: 'Chica',
      precioVentaMenor: 2000,
      orden: 0,
    ),
  ],
);

Future<void> _pumpArticle(WidgetTester tester, ArticuloListado article) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InventoryArticleCard(articulo: article)),
      ),
    );

ArticuloListado _stockArticle({
  int secondBalance = 0,
  bool removeSecond = false,
}) => ArticuloListado(
  productoId: 'flour',
  nombre: 'Harina',
  activo: true,
  categoriaId: null,
  categoriaNombre: null,
  categoriaColor: null,
  unidadVenta: _kilogram,
  cantidadReferenciaPrecioAtomica: 1000,
  variantesActivas: [
    VarianteListado(
      varianteId: 'first',
      nombre: null,
      precioVentaMenor: 15400,
      orden: 0,
      inventario: _inventory('first', 2500),
    ),
    if (!removeSecond)
      VarianteListado(
        varianteId: 'second',
        nombre: 'Vacía',
        precioVentaMenor: 10000,
        orden: 1,
        inventario: _inventory('second', secondBalance),
      ),
    const VarianteListado(
      varianteId: 'third',
      nombre: 'Sin seguimiento',
      precioVentaMenor: 8000,
      orden: 2,
    ),
  ],
);

RecursoInventarioListado _inventory(String id, int balance) =>
    RecursoInventarioListado(
      id: id,
      nombre: 'Harina',
      activo: true,
      existenciaAtomica: balance,
      unidadPredeterminada: _kilogram,
    );

const _kilogram = UnidadInventario(
  id: 'kg',
  code: 'kg',
  nombre: 'Kilogramo',
  simbolo: 'kg',
  dimension: DimensionUnidad.mass,
  factorAtomico: 1000,
  maximosDecimales: 3,
  activa: true,
);
