import 'package:pos_flutter/domain/articulos/variante_por_codigo_barras.dart';
import 'dart:async';

import 'package:pos_flutter/domain/articulos/articulo_detalle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pos_flutter/application/export/articulo_catalog_export_service.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/articulo_vinculado_categoria.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/inventory_articles_tab.dart';

void main() {
  testWidgets('muestra datos sin controles fuera del alcance', (tester) async {
    await _pumpTab(tester, repository: _FakeProductoRepository(_articles));

    expect(find.text('Café americano'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pastel'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Pastel'), findsOneWidget);
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

  testWidgets('el botón de CSV va después de Filtros en la misma fila', (
    tester,
  ) async {
    await _pumpTab(tester, repository: _FakeProductoRepository(_articles));

    final filtros = tester.getTopLeft(
      find.byKey(const Key('open_article_filters_button')),
    );
    final exportar = tester.getTopLeft(
      find.byKey(const Key('export_articles_csv_button')),
    );

    expect(exportar.dx, greaterThan(filtros.dx));
    // La barra es una fila horizontal con scroll: los controles comparten dy.
    expect(exportar.dy, filtros.dy);
  });

  testWidgets('el botón exporta con los filtros aplicados y avisa el conteo', (
    tester,
  ) async {
    final exportService = _FakeExportService();
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      exportService: exportService,
    );

    await _applyCategory(tester, 'category-1');
    await tester.tap(find.byKey(const Key('export_articles_csv_button')));
    await tester.pumpAndSettle();

    // La presentación pasa el filtro; el servicio no lee estado de la UI.
    expect(exportService.filtros, hasLength(1));
    expect(exportService.filtros.single.categoryIds, {'category-1'});
    expect(exportService.filtros.single.incluirSinCategoria, isFalse);
    expect(exportService.filtros.single.busqueda, '');
    expect(
      find.text('Se exportan 2 de 4 artículos con los filtros aplicados.'),
      findsOneWidget,
    );
  });

  testWidgets('la búsqueda también viaja como parámetro del filtro', (
    tester,
  ) async {
    final exportService = _FakeExportService();
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      exportService: exportService,
      search: 'café',
    );

    await tester.tap(find.byKey(const Key('export_articles_csv_button')));
    await tester.pumpAndSettle();

    expect(exportService.filtros.single.busqueda, 'café');
    expect(exportService.filtros.single.categoryIds, isEmpty);
  });

  testWidgets('Sin categoría viaja como parte del filtro aplicado', (
    tester,
  ) async {
    final exportService = _FakeExportService();
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      exportService: exportService,
    );

    await tester.tap(find.byKey(const Key('open_article_filters_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('article_filter_without_category')));
    await tester.tap(find.byKey(const Key('apply_article_filters_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('export_articles_csv_button')));
    await tester.pumpAndSettle();

    expect(exportService.filtros.single.incluirSinCategoria, isTrue);
  });

  testWidgets('sin filtros el archivo es el catálogo completo y lo dice', (
    tester,
  ) async {
    final exportService = _FakeExportService();
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      exportService: exportService,
    );

    await tester.tap(find.byKey(const Key('export_articles_csv_button')));
    await tester.pumpAndSettle();

    expect(exportService.filtros.single.hayFiltros, isFalse);
    expect(find.text('Se exportó el catálogo: 4 artículos.'), findsOneWidget);
  });

  testWidgets('el archivo del servicio se comparte con su nombre', (
    tester,
  ) async {
    ShareParams? compartida;
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      shareFile: (params) async {
        compartida = params;
        return const ShareResult('', ShareResultStatus.success);
      },
    );

    await tester.tap(find.byKey(const Key('export_articles_csv_button')));
    await tester.pumpAndSettle();

    expect(compartida, isNotNull);
    final params = compartida!;
    expect(params.files!.single.path, '/tmp/catalogo_2026-09-30.csv');
    expect(params.fileNameOverrides, ['catalogo_2026-09-30.csv']);
  });

  testWidgets('una falla al exportar avisa y rehabilita el botón', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      exportService: _FakeExportService(falla: true),
    );

    await tester.tap(find.byKey(const Key('export_articles_csv_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo exportar el catálogo. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    final boton = tester.widget<OutlinedButton>(
      find.byKey(const Key('export_articles_csv_button')),
    );
    expect(boton.onPressed, isNotNull);
  });

  testWidgets('el botón de PDF va al lado del de CSV en la misma fila', (
    tester,
  ) async {
    await _pumpTab(tester, repository: _FakeProductoRepository(_articles));

    final csv = tester.getTopLeft(
      find.byKey(const Key('export_articles_csv_button')),
    );
    final pdf = tester.getTopLeft(
      find.byKey(const Key('export_articles_pdf_button')),
    );

    expect(pdf.dx, greaterThan(csv.dx));
    // La barra es una fila horizontal con scroll: los controles comparten dy.
    expect(pdf.dy, csv.dy);
  });

  testWidgets(
    'el botón de PDF exporta con los filtros aplicados y avisa el conteo',
    (tester) async {
      final exportService = _FakeExportService();
      await _pumpTab(
        tester,
        repository: _FakeProductoRepository(_articles),
        exportService: exportService,
      );

      await _applyCategory(tester, 'category-1');
      await tester.tap(find.byKey(const Key('export_articles_pdf_button')));
      await tester.pumpAndSettle();

      // El PDF usa el método de PDF, no el de CSV: son dos artefactos (D8).
      expect(exportService.formatos, ['pdf']);
      expect(exportService.filtros.single.categoryIds, {'category-1'});
      expect(
        find.text('Se exportan 2 de 4 artículos con los filtros aplicados.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('el PDF se comparte con su nombre y con su extensión', (
    tester,
  ) async {
    ShareParams? compartida;
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      exportService: _FakeExportService(),
      shareFile: (params) async {
        compartida = params;
        return const ShareResult('', ShareResultStatus.success);
      },
    );

    await tester.tap(find.byKey(const Key('export_articles_pdf_button')));
    await tester.pumpAndSettle();

    expect(compartida!.files!.single.path, '/tmp/catalogo_2026-09-30.pdf');
    expect(compartida!.fileNameOverrides, ['catalogo_2026-09-30.pdf']);
  });

  testWidgets('mientras se genera un formato, el otro botón queda bloqueado', (
    tester,
  ) async {
    final exportService = _LentaExportService();
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      exportService: exportService,
    );

    await tester.tap(find.byKey(const Key('export_articles_pdf_button')));
    await tester.pump();

    // Los dos se bloquean juntos: dos archivos compitiendo por el directorio
    // temporal y dos diálogos de compartir no son un estado que el usuario quiera.
    final csv = tester.widget<OutlinedButton>(
      find.byKey(const Key('export_articles_csv_button')),
    );
    final pdf = tester.widget<OutlinedButton>(
      find.byKey(const Key('export_articles_pdf_button')),
    );
    expect(pdf.onPressed, isNull);
    expect(csv.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Se suelta la exportación y el spinner desaparece: por eso no se puede
    // usar `pumpAndSettle` mientras está generando, el indicador no para nunca.
    exportService.permiso.complete();
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('export_articles_csv_button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('export_articles_pdf_button')),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(exportService.formatos, ['pdf']);
  });

  testWidgets('una falla al generar el PDF avisa lo mismo que el CSV', (
    tester,
  ) async {
    await _pumpTab(
      tester,
      repository: _FakeProductoRepository(_articles),
      exportService: _FakeExportService(falla: true),
    );

    await tester.tap(find.byKey(const Key('export_articles_pdf_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo exportar el catálogo. Inténtalo de nuevo.'),
      findsOneWidget,
    );
  });
}

/// Exportación que no termina hasta que el test la suelta, para poder mirar los
/// botones mientras el archivo se está generando.
class _LentaExportService implements ArticuloCatalogExportService {
  final List<String> formatos = [];
  final Completer<void> permiso = Completer<void>();

  @override
  Future<ArticuloExportArchivo> exportarCatalogo(
    ArticuloExportFiltro filtro,
  ) async {
    formatos.add('csv');
    await permiso.future;
    return _archivo(filtro, '/tmp/catalogo_2026-09-30.csv');
  }

  @override
  Future<ArticuloExportArchivo> exportarCatalogoPdf(
    ArticuloExportFiltro filtro,
  ) async {
    formatos.add('pdf');
    await permiso.future;
    return _archivo(filtro, '/tmp/catalogo_2026-09-30.pdf');
  }

  ArticuloExportArchivo _archivo(ArticuloExportFiltro filtro, String ruta) {
    return ArticuloExportArchivo(
      ruta: ruta,
      productos: 4,
      filas: 4,
      productosTotales: filtro.hayFiltros ? 4 : null,
    );
  }

  @override
  Future<ArticuloExportArchivo> exportarPlantilla() async =>
      const ArticuloExportArchivo(
        ruta: '/tmp/plantilla.csv',
        productos: 0,
        filas: 0,
      );

  @override
  Future<ArticuloExportArchivo> exportarNotasColumnas() async =>
      const ArticuloExportArchivo(
        ruta: '/tmp/notas.csv',
        productos: 0,
        filas: 0,
      );
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required ProductoRepository repository,
  CategoriaRepository categoriaRepository = const _FakeCategoriaRepository(
    _categories,
  ),
  String search = '',
  VoidCallback? onClearSearch,
  ArticuloCatalogExportService? exportService,
  Future<ShareResult> Function(ShareParams)? shareFile,
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
          exportService: exportService ?? _FakeExportService(),
          // Por defecto no se comparte de verdad: `share_plus` necesita una
          // plataforma detrás y en pruebas no resuelve.
          shareFile:
              shareFile ??
              (params) async =>
                  const ShareResult('', ShareResultStatus.success),
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
  @override
  Future<List<VariantePorCodigoBarras>> buscarVariantesPorCodigoBarras(
    String codigo,
  ) async => const [];

  @override
  Future<ArticuloDetalle?> obtenerDetalle(String productoId) async => null;

  _FakeProductoRepository(this.articles);

  final List<ArticuloListado> articles;
  final List<_Query> queries = [];

  @override
  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  ) async => const [];

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

  @override
  Stream<int> watchVariantesActivasCount() => throw UnimplementedError();
}

class _SequencedProductoRepository implements ProductoRepository {
  @override
  Future<List<VariantePorCodigoBarras>> buscarVariantesPorCodigoBarras(
    String codigo,
  ) async => const [];

  @override
  Future<ArticuloDetalle?> obtenerDetalle(String productoId) async => null;

  _SequencedProductoRepository(this.streams);

  final List<Stream<List<ArticuloListado>>> streams;
  int subscriptions = 0;

  @override
  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  ) async => const [];

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

  @override
  Stream<int> watchVariantesActivasCount() => throw UnimplementedError();
}

class _FakeExportService implements ArticuloCatalogExportService {
  _FakeExportService({this.falla = false});

  final bool falla;
  final List<ArticuloExportFiltro> filtros = [];
  final List<String> formatos = [];

  @override
  Future<ArticuloExportArchivo> exportarCatalogo(
    ArticuloExportFiltro filtro,
  ) async {
    formatos.add('csv');
    return _archivo(filtro, '/tmp/catalogo_2026-09-30.csv');
  }

  @override
  Future<ArticuloExportArchivo> exportarCatalogoPdf(
    ArticuloExportFiltro filtro,
  ) async {
    formatos.add('pdf');
    return _archivo(filtro, '/tmp/catalogo_2026-09-30.pdf');
  }

  Future<ArticuloExportArchivo> _archivo(
    ArticuloExportFiltro filtro,
    String ruta,
  ) async {
    filtros.add(filtro);
    if (falla) {
      throw StateError('export error');
    }
    final productos = filtro.hayFiltros ? 2 : 4;
    final productosTotales = filtro.hayFiltros ? 4 : null;
    return ArticuloExportArchivo(
      ruta: ruta,
      productos: productos,
      filas: productos,
      productosTotales: productosTotales,
    );
  }

  @override
  Future<ArticuloExportArchivo> exportarPlantilla() async {
    return const ArticuloExportArchivo(
      ruta: '/tmp/plantilla.csv',
      productos: 0,
      filas: 0,
    );
  }

  @override
  Future<ArticuloExportArchivo> exportarNotasColumnas() async {
    return const ArticuloExportArchivo(
      ruta: '/tmp/notas.csv',
      productos: 0,
      filas: 0,
    );
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
    variantesActivas: [
      VarianteListado(
        varianteId: 'variant-coffee',
        nombre: null,
        precioVentaMenor: 4550,
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
    variantesActivas: [
      VarianteListado(
        varianteId: 'variant-tea',
        nombre: null,
        precioVentaMenor: 3200,
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
    variantesActivas: [
      VarianteListado(
        varianteId: 'variant-water',
        nombre: null,
        precioVentaMenor: 2000,
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
    variantesActivas: [
      VarianteListado(
        varianteId: 'variant-cake',
        nombre: null,
        precioVentaMenor: 6000,
        orden: 0,
      ),
    ],
  ),
];
