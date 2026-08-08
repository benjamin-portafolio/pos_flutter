import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/inventory_article_card.dart';

void main() {
  testWidgets('muestra un artículo sencillo sin categoría ni chip redundante', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InventoryArticleCard(articulo: _withoutCategory)),
      ),
    );

    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    expect(find.text('Café americano'), findsOneWidget);
    expect(find.text(r'$45.50'), findsOneWidget);
    expect(find.text('Sin categoría'), findsNothing);
    expect(find.byType(Chip), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(
      find.bySemanticsLabel(r'Café americano, sin categoría, $45.50'),
      findsOneWidget,
    );
  });

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

  testWidgets('compone variantes nombradas futuras en orden', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InventoryArticleCard(articulo: _withNamedVariants),
        ),
      ),
    );

    final chips = tester.widgetList<Chip>(find.byType(Chip)).toList();
    expect(chips, hasLength(2));
    expect((chips[0].label as Text).data, r'Chica · $20.00');
    expect((chips[1].label as Text).data, r'Grande · $30.00');
    expect(find.text('Variante sencilla'), findsNothing);
  });

  testWidgets('no usa imágenes ni ofrece una edición inexistente', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: InventoryArticleCard(articulo: _withoutCategory)),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    expect(find.text('Editar'), findsNothing);
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
    expect(find.text('Refresco'), findsOneWidget);
    expect(find.byType(Chip), findsNWidgets(2));
  });
}

const _withoutCategory = ArticuloListado(
  productoId: 'product-coffee',
  nombre: 'Café americano',
  activo: true,
  categoriaId: null,
  categoriaNombre: null,
  categoriaColor: null,
  variantePredeterminadaId: 'variant-coffee',
  precioPredeterminadoMenor: 4550,
  variantesActivas: [
    VarianteListado(
      varianteId: 'variant-coffee',
      nombre: null,
      precioVentaMenor: 4550,
      predeterminada: true,
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
  variantePredeterminadaId: 'variant-tea',
  precioPredeterminadoMenor: 3200,
  variantesActivas: [
    VarianteListado(
      varianteId: 'variant-tea',
      nombre: null,
      precioVentaMenor: 3200,
      predeterminada: true,
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
  variantePredeterminadaId: 'variant-large',
  precioPredeterminadoMenor: 3000,
  variantesActivas: [
    VarianteListado(
      varianteId: 'variant-large',
      nombre: 'Grande',
      precioVentaMenor: 3000,
      predeterminada: true,
      orden: 1,
    ),
    VarianteListado(
      varianteId: 'variant-simple',
      nombre: null,
      precioVentaMenor: 1500,
      predeterminada: false,
      orden: 2,
    ),
    VarianteListado(
      varianteId: 'variant-small',
      nombre: 'Chica',
      precioVentaMenor: 2000,
      predeterminada: false,
      orden: 0,
    ),
  ],
);
