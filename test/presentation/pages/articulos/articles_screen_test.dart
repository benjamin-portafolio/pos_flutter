import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/articulos/articulo_detalle.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/articulo_vinculado_categoria.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/domain/repositories/sale_draft_repository.dart';
import 'package:pos_flutter/presentation/pages/articulos/articles_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/home_screen.dart';

import '../../../support/fake_sale_draft_repository.dart';

void main() {
  testWidgets(
    'abre Artículos con buscador y conserva los otros controles inertes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      getIt.registerSingleton<CategoriaRepository>(
        _Categories(Stream.value(_categories)),
      );
      getIt.registerSingleton<ProductoRepository>(
        _Products(Stream.value([_article])),
      );
      getIt.registerSingleton<SaleDraftRepository>(FakeSaleDraftRepository());
      addTearDown(getIt.reset);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.tap(find.text('Artículos'));
      await tester.pumpAndSettle();

      expect(find.byType(ArticlesScreen), findsOneWidget);
      expect(find.text('Bebidas (1)'), findsOneWidget);
      expect(find.text('Alimentos (0)'), findsOneWidget);
      final searchField = tester.widget<TextField>(find.byType(TextField));
      expect(searchField.readOnly, isTrue);
      expect(searchField.onTap, isNotNull);
      for (final tooltip in ['Código de barras', 'Alta rápida de artículo']) {
        final button = find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == tooltip,
        );
        expect(tester.widget<IconButton>(button).onPressed, isNull);
        await tester.tap(button);
      }
      await tester.tap(find.text('Bebidas (1)'));
      await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsNothing);
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actualiza conteos y orden sin perder la selección por categoría',
    (tester) async {
      final categories = StreamController<List<Categoria>>();
      final products = StreamController<List<ArticuloListado>>();
      addTearDown(categories.close);
      addTearDown(products.close);
      await _pumpScreen(tester, categories.stream, products.stream);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      categories.add(_categories);
      await tester.pump();
      products.add([_article]);
      await tester.pumpAndSettle();

      // Un producto con dos variantes cuenta como un solo artículo.
      expect(find.text('Bebidas (1)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Bebidas (1)')).dy,
        lessThan(tester.getTopLeft(find.text('Alimentos (0)')).dy),
      );
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isTrue,
      );

      categories.add(_categories.reversed.toList());
      products.add([]);
      await tester.pumpAndSettle();
      expect(find.text('Bebidas (0)'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Alimentos (0)')).dy,
        lessThan(tester.getTopLeft(find.text('Bebidas (0)')).dy),
      );
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).first).value,
        isFalse,
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isTrue);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox).last).value,
        isFalse,
      );
    },
  );

  testWidgets('muestra catálogo vacío', (tester) async {
    await _pumpScreen(tester, Stream.value([]), Stream.value([]));
    await tester.pumpAndSettle();
    expect(find.text('No hay categorías.'), findsOneWidget);
  });

  testWidgets('muestra errores de categorías', (tester) async {
    await _pumpScreen(
      tester,
      Stream.error(StateError('lectura')),
      Stream.value([]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar las categorías.'), findsOneWidget);
  });

  testWidgets('no confunde un error de artículos con conteos en cero', (
    tester,
  ) async {
    final products = StreamController<List<ArticuloListado>>();
    addTearDown(products.close);
    await _pumpScreen(tester, Stream.value(_categories), products.stream);
    await tester.pump();
    products.addError(StateError('lectura'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar los artículos.'), findsOneWidget);
    expect(find.text('Bebidas (0)'), findsNothing);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Stream<List<Categoria>> categories,
  Stream<List<ArticuloListado>> products,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ArticlesScreen(
          categoriaRepository: _Categories(categories),
          productoRepository: _Products(products),
        ),
      ),
    ),
  );
}

class _Categories implements CategoriaRepository {
  _Categories(this.stream);
  final Stream<List<Categoria>> stream;

  @override
  Stream<List<Categoria>> watchCategorias() => stream;

  @override
  Future<List<Categoria>> obtenerCategorias() => throw UnimplementedError();
}

class _Products implements ProductoRepository {
  _Products(this.stream);
  final Stream<List<ArticuloListado>> stream;

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const {},
    bool incluirSinCategoria = false,
  }) => stream;

  @override
  Future<ArticuloDetalle?> obtenerDetalle(String productoId) =>
      throw UnimplementedError();

  @override
  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  ) => throw UnimplementedError();
}

const _categories = [
  Categoria(
    id: 'drinks',
    nombre: 'Bebidas',
    color: ColorCategoria.cyan,
    orden: 0,
  ),
  Categoria(
    id: 'food',
    nombre: 'Alimentos',
    color: ColorCategoria.yellow,
    orden: 1,
  ),
];

const _article = ArticuloListado(
  productoId: 'coffee',
  nombre: 'Café',
  activo: true,
  categoriaId: 'drinks',
  categoriaNombre: 'Bebidas',
  categoriaColor: ColorCategoria.cyan,
  variantesActivas: [
    VarianteListado(
      varianteId: 'small',
      nombre: 'Chico',
      precioVentaMenor: 2500,
      orden: 0,
    ),
    VarianteListado(
      varianteId: 'large',
      nombre: 'Grande',
      precioVentaMenor: 3500,
      orden: 1,
    ),
  ],
);
