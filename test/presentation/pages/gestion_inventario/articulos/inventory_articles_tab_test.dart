import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/inventory_articles_tab.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/inventory_article_card.dart';

void main() {
  testWidgets('muestra datos sin controles fuera del alcance', (tester) async {
    await _pumpTab(tester, repository: _FakeProductoRepository(_articles));

    expect(find.byType(InventoryArticleCard), findsNWidgets(4));
    expect(find.text('Inventario bajo'), findsNothing);
    expect(find.text('Expirado'), findsNothing);
    expect(find.text('Etiquetas'), findsNothing);
    expect(find.text('Espacios'), findsNothing);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'mantiene el borrador separado y aplica categorías y Sin categoría con OR',
    (tester) async {
      final repository = _FakeProductoRepository(_articles);
      await _pumpTab(tester, repository: repository);

      await tester.tap(find.byKey(const Key('open_article_filters_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('article_filter_category_category-1')),
      );
      await tester.tap(
        find.byKey(const Key('article_filter_category_category-2')),
      );
      await tester.tap(
        find.byKey(const Key('article_filter_without_category')),
      );
      await tester.pump();

      expect(repository.queries, hasLength(1));

      await tester.tap(find.byKey(const Key('apply_article_filters_button')));
      await tester.pumpAndSettle();

      expect(repository.queries.last.categoryIds, {'category-1', 'category-2'});
      expect(repository.queries.last.includeUncategorized, isTrue);
      expect(find.text('Café americano'), findsOneWidget);
      expect(find.text('Té verde'), findsOneWidget);
      expect(find.text('Agua mineral'), findsOneWidget);
      expect(find.text('Pastel'), findsNothing);
      expect(
        find.bySemanticsLabel('Filtrar artículos, 3 filtros aplicados'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Cerrar, back y descarte abandonan el borrador', (tester) async {
    final repository = _FakeProductoRepository(_articles);
    await _pumpTab(tester, repository: repository);
    await _applyCategory(tester, 'category-1');
    expect(repository.queries.last.categoryIds, {'category-1'});

    await _openAndSelectCategory(tester, 'category-2');
    await tester.tap(find.byKey(const Key('close_article_filters_button')));
    await tester.pumpAndSettle();
    expect(repository.queries.last.categoryIds, {'category-1'});

    await _openAndSelectCategory(tester, 'category-2');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(repository.queries.last.categoryIds, {'category-1'});

    await _openAndSelectCategory(tester, 'category-2');
    await tester.drag(
      find.byKey(const Key('article_filters_bottom_sheet')),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article_filters_bottom_sheet')), findsNothing);
    expect(repository.queries.last.categoryIds, {'category-1'});
    expect(find.text('Café americano'), findsOneWidget);
    expect(find.text('Té verde'), findsNothing);
  });

  testWidgets(
    'Restablecer no cierra, Aplicar confirma y Todos conserva texto',
    (tester) async {
      final repository = _FakeProductoRepository(_articles);
      await _pumpTab(tester, repository: repository, search: 'a');
      await _applyCategory(tester, 'category-1');

      await tester.tap(find.byKey(const Key('open_article_filters_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reset_article_filters_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('article_filters_bottom_sheet')),
        findsOneWidget,
      );
      expect(repository.queries.last.categoryIds, {'category-1'});

      await tester.tap(find.byKey(const Key('apply_article_filters_button')));
      await tester.pumpAndSettle();
      expect(repository.queries.last.categoryIds, isEmpty);
      expect(repository.queries.last.search, 'a');

      await _applyCategory(tester, 'category-2');
      await tester.tap(find.byKey(const Key('all_articles_filter_chip')));
      await tester.pumpAndSettle();

      expect(repository.queries.last.categoryIds, isEmpty);
      expect(repository.queries.last.includeUncategorized, isFalse);
      expect(repository.queries.last.search, 'a');
    },
  );

  testWidgets('distingue carga inicial y catálogo vacío', (tester) async {
    await _pumpTab(
      tester,
      repository: _SequencedProductoRepository([
        const Stream<List<ArticuloListado>>.empty(),
      ]),
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpTab(tester, repository: _FakeProductoRepository(const []));
    expect(find.text('No hay artículos.'), findsOneWidget);
    expect(
      find.byKey(const Key('add_article_from_empty_state_button')),
      findsOneWidget,
    );
  });

  testWidgets('distingue búsqueda sin resultados y permite limpiarla', (
    tester,
  ) async {
    var cleared = false;
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      search: 'inexistente',
      onClearSearch: () => cleared = true,
    );

    expect(find.text('No se encontraron artículos.'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('clear_search_from_empty_state_button')),
    );
    expect(cleared, isTrue);
  });

  testWidgets('muestra error y Reintentar crea una nueva suscripción', (
    tester,
  ) async {
    final repository = _SequencedProductoRepository([
      Stream<List<ArticuloListado>>.error(StateError('fallo de lectura')),
      Stream.value([_articles.first]),
    ]);
    await _pumpTab(tester, repository: repository, settle: false);
    await tester.pump();

    expect(find.text('No se pudieron cargar los artículos.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry_articles_button')));
    await tester.pumpAndSettle();

    expect(find.text('Café americano'), findsOneWidget);
    expect(repository.subscriptions, 2);
  });

  testWidgets('el panel vacío conserva la opción Sin categoría', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      categoriaRepository: _FakeCategoriaRepository(const []),
    );

    await tester.tap(find.byKey(const Key('open_article_filters_button')));
    await tester.pumpAndSettle();

    expect(find.text('No hay categorías.'), findsOneWidget);
    expect(
      find.byKey(const Key('article_filter_without_category')),
      findsOneWidget,
    );
  });
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required ProductoRepository repository,
  CategoriaRepository categoriaRepository = const _FakeCategoriaRepository(
    _categories,
  ),
  String search = '',
  VoidCallback? onClearSearch,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InventoryArticlesTab(
          productoRepository: repository,
          categoriaRepository: categoriaRepository,
          busqueda: search,
          onClearSearch: onClearSearch ?? () {},
          onAddArticle: () {},
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _applyCategory(WidgetTester tester, String categoryId) async {
  await _openAndSelectCategory(tester, categoryId);
  await tester.tap(find.byKey(const Key('apply_article_filters_button')));
  await tester.pumpAndSettle();
}

Future<void> _openAndSelectCategory(
  WidgetTester tester,
  String categoryId,
) async {
  await tester.tap(find.byKey(const Key('open_article_filters_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('article_filter_category_$categoryId')));
  await tester.pump();
}

class _FakeProductoRepository implements ProductoRepository {
  _FakeProductoRepository(this.articles);

  final List<ArticuloListado> articles;
  final List<_Query> queries = [];

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) {
    final query = _Query(
      search: busqueda,
      categoryIds: Set.of(categoriaIds),
      includeUncategorized: incluirSinCategoria,
    );
    queries.add(query);
    final normalizedSearch = busqueda.trim().toLowerCase();
    final hasCategoryFilter = categoriaIds.isNotEmpty || incluirSinCategoria;
    return Stream.value(
      articles
          .where((article) {
            final matchesSearch =
                normalizedSearch.isEmpty ||
                article.nombre.toLowerCase().contains(normalizedSearch);
            final matchesCategory =
                !hasCategoryFilter ||
                (article.categoriaId == null
                    ? incluirSinCategoria
                    : categoriaIds.contains(article.categoriaId));
            return matchesSearch && matchesCategory;
          })
          .toList(growable: false),
    );
  }
}

class _SequencedProductoRepository implements ProductoRepository {
  _SequencedProductoRepository(this.streams);

  final List<Stream<List<ArticuloListado>>> streams;
  int subscriptions = 0;

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) {
    final index = subscriptions.clamp(0, streams.length - 1);
    subscriptions++;
    return streams[index];
  }
}

class _Query {
  const _Query({
    required this.search,
    required this.categoryIds,
    required this.includeUncategorized,
  });

  final String search;
  final Set<String> categoryIds;
  final bool includeUncategorized;
}

class _FakeCategoriaRepository implements CategoriaRepository {
  const _FakeCategoriaRepository(this.categories);

  final List<Categoria> categories;

  @override
  Future<List<Categoria>> obtenerCategorias() async => categories;

  @override
  Stream<List<Categoria>> watchCategorias() => Stream.value(categories);
}

const _categories = [
  Categoria(
    id: 'category-1',
    nombre: 'Bebidas',
    color: ColorCategoria.blue,
    orden: 0,
  ),
  Categoria(
    id: 'category-2',
    nombre: 'Tés',
    color: ColorCategoria.green,
    orden: 1,
  ),
  Categoria(
    id: 'category-3',
    nombre: 'Postres',
    color: ColorCategoria.pink,
    orden: 2,
  ),
];

const _articles = [
  ArticuloListado(
    productoId: 'product-coffee',
    nombre: 'Café americano',
    activo: true,
    categoriaId: 'category-1',
    categoriaNombre: 'Bebidas',
    categoriaColor: ColorCategoria.blue,
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
  ),
  ArticuloListado(
    productoId: 'product-tea',
    nombre: 'Té verde',
    activo: true,
    categoriaId: 'category-2',
    categoriaNombre: 'Tés',
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
  ),
  ArticuloListado(
    productoId: 'product-water',
    nombre: 'Agua mineral',
    activo: true,
    categoriaId: null,
    categoriaNombre: null,
    categoriaColor: null,
    variantePredeterminadaId: 'variant-water',
    precioPredeterminadoMenor: 2000,
    variantesActivas: [
      VarianteListado(
        varianteId: 'variant-water',
        nombre: null,
        precioVentaMenor: 2000,
        predeterminada: true,
        orden: 0,
      ),
    ],
  ),
  ArticuloListado(
    productoId: 'product-cake',
    nombre: 'Pastel',
    activo: true,
    categoriaId: 'category-3',
    categoriaNombre: 'Postres',
    categoriaColor: ColorCategoria.pink,
    variantePredeterminadaId: 'variant-cake',
    precioPredeterminadoMenor: 6000,
    variantesActivas: [
      VarianteListado(
        varianteId: 'variant-cake',
        nombre: null,
        precioVentaMenor: 6000,
        predeterminada: true,
        orden: 0,
      ),
    ],
  ),
];
