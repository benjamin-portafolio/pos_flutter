import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/presentation/pages/articulos/article_search_screen.dart';
import 'package:pos_flutter/presentation/pages/articulos/articles_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/categorias/category_color_palette.dart';

void main() {
  testWidgets('abre con recientes de todo el catálogo y regresa a categorías', (
    tester,
  ) async {
    _phoneSize(tester);
    final repository = _Products(() => Stream.value(_catalog));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArticlesScreen(
            productoRepository: repository,
            categoriaRepository: _Categories(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.byType(ArticleSearchScreen), findsOneWidget);
    expect(find.text('Recientemente añadidos'), findsOneWidget);
    expect(find.text('Pan'), findsOneWidget);
    expect(find.text('Café'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Pan')).dx,
      lessThan(tester.getTopLeft(find.text('Café').first).dx),
    );
    expect(tester.testTextInput.isVisible, isTrue);
    expect(repository.calls, 2);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleSearchScreen), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Recientemente añadidos'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'filtra producto y variante, limpia y no actúa al tocar mosaicos',
    (tester) async {
      _phoneSize(tester);
      final repository = _Products(() => Stream.value(_catalog));
      await _pump(tester, repository);
      await tester.enterText(find.byType(TextField), 'café');
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsNWidgets(2));
      expect(find.text('Pan'), findsNothing);

      await tester.enterText(find.byType(TextField), 'grande');
      await tester.pumpAndSettle();
      expect(find.text('Grande'), findsOneWidget);
      expect(find.text('Chico'), findsNothing);

      await tester.enterText(find.byType(TextField), '  CAFÉ   gran ');
      await tester.pumpAndSettle();
      expect(find.text('Café'), findsOneWidget);
      expect(find.text(r'$35.50'), findsOneWidget);
      await tester.tap(find.byType(Card));
      await tester.pumpAndSettle();
      expect(find.byType(ArticleSearchScreen), findsOneWidget);
      expect(find.text('Grande'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'inexistente');
      await tester.pumpAndSettle();
      expect(find.text('No se encontraron artículos.'), findsOneWidget);
      await tester.tap(find.byTooltip('Limpiar búsqueda'));
      await tester.pumpAndSettle();
      expect(find.text('Recientemente añadidos'), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(3));
      expect(repository.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'muestra precio, nombre opcional y círculos con color de categoría',
    (tester) async {
      await _pump(tester, _Products(() => Stream.value(_catalog)));
      Color circleColor(String variantId) {
        final circle = find.descendant(
          of: find.byKey(ValueKey(variantId)),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
          ),
        );
        return (tester.widget<Container>(circle).decoration! as BoxDecoration)
            .color!;
      }

      expect(
        circleColor('bread'),
        CategoryColorPalette.resolve(ColorCategoria.grey),
      );
      expect(
        circleColor('large'),
        CategoryColorPalette.resolve(ColorCategoria.cyan),
      );
      expect(find.text('Pan'), findsOneWidget);
      expect(find.text('null'), findsNothing);
      expect(find.text(r'$20.00'), findsOneWidget);
      expect(find.text(r'$25.00'), findsOneWidget);
      expect(find.text(r'$35.50'), findsOneWidget);
    },
  );

  testWidgets('observa cambios locales sin perder el texto de búsqueda', (
    tester,
  ) async {
    final controller = StreamController<List<ArticuloListado>>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: ArticleSearchScreen(
          productoRepository: _Products(() => controller.stream),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    controller.add([]);
    await tester.pumpAndSettle();
    expect(find.text('No hay artículos.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'café grande');
    controller.add(_catalog);
    await tester.pumpAndSettle();
    expect(find.text('Grande'), findsOneWidget);
    expect(find.text('Chico'), findsNothing);
    controller.add([_catalog.last]);
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron artículos.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'café grande',
    );

    controller.addError(StateError('lectura'));
    await tester.pumpAndSettle();
    expect(find.text('No se pudieron cargar los artículos.'), findsOneWidget);
    expect(find.text('No se encontraron artículos.'), findsNothing);
  });

  testWidgets(
    'admite nombres largos y texto ampliado en teléfono con teclado',
    (tester) async {
      _phoneSize(tester, width: 320);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      final longName = ArticuloListado(
        productoId: 'long',
        nombre: 'Producto con un nombre muy largo para mostrar en un mosaico',
        activo: true,
        categoriaId: null,
        categoriaNombre: null,
        categoriaColor: null,
        variantesActivas: const [
          VarianteListado(
            varianteId: 'long-variant',
            nombre:
                'Una variante de nombre muy largo que ocupa más de una línea',
            precioVentaMenor: 99999999,
            orden: 0,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ArticleSearchScreen(
            productoRepository: _Products(() => Stream.value([longName])),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _phoneSize(WidgetTester tester, {double width = 360}) {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, ProductoRepository repository) async {
  await tester.pumpWidget(
    MaterialApp(home: ArticleSearchScreen(productoRepository: repository)),
  );
  await tester.pumpAndSettle();
}

class _Products implements ProductoRepository {
  _Products(this.stream);
  final Stream<List<ArticuloListado>> Function() stream;
  int calls = 0;

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const {},
    bool incluirSinCategoria = false,
  }) {
    expect(busqueda, isEmpty);
    expect(categoriaIds, isEmpty);
    expect(incluirSinCategoria, isFalse);
    calls++;
    return stream();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Categories implements CategoriaRepository {
  @override
  Stream<List<Categoria>> watchCategorias() => Stream.value(const [
    Categoria(
      id: 'drinks',
      nombre: 'Bebidas',
      color: ColorCategoria.cyan,
      orden: 0,
    ),
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _catalog = [
  ArticuloListado(
    productoId: 'coffee',
    nombre: 'Café',
    activo: true,
    categoriaId: 'drinks',
    categoriaNombre: 'Bebidas',
    categoriaColor: ColorCategoria.cyan,
    fechaCreacion: DateTime(2026, 9, 10),
    variantesActivas: const [
      VarianteListado(
        varianteId: 'small',
        nombre: 'Chico',
        precioVentaMenor: 2500,
        orden: 0,
      ),
      VarianteListado(
        varianteId: 'large',
        nombre: 'Grande',
        precioVentaMenor: 3550,
        orden: 1,
      ),
    ],
  ),
  ArticuloListado(
    productoId: 'bread',
    nombre: 'Pan',
    activo: true,
    categoriaId: null,
    categoriaNombre: null,
    categoriaColor: null,
    fechaCreacion: DateTime(2026, 9, 11),
    variantesActivas: const [
      VarianteListado(
        varianteId: 'bread',
        nombre: null,
        precioVentaMenor: 2000,
        orden: 0,
      ),
    ],
  ),
];
