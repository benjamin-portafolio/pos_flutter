import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/categoria_command_service.dart';
import 'package:pos_flutter/application/commands/crear_categoria_command.dart';
import 'package:pos_flutter/application/commands/editar_categoria_command.dart';
import 'package:pos_flutter/application/commands/eliminar_categoria_command.dart';
import 'package:pos_flutter/application/commands/mover_categoria_command.dart';
import 'package:pos_flutter/application/commands/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/producto_command_service.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/domain/articulos/articulo_vinculado_categoria.dart';
import 'package:pos_flutter/domain/articulos/variante_listado.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
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
  final productoRepository = _FakeProductoRepository(const [
    ArticuloListado(
      productoId: 'product-1',
      nombre: 'Café',
      activo: true,
      categoriaId: 'category-1',
      categoriaNombre: 'Bebidas',
      categoriaColor: ColorCategoria.blue,
      variantePredeterminadaId: 'variant-1',
      precioPredeterminadoMenor: 4550,
      variantesActivas: [
        VarianteListado(
          varianteId: 'variant-1',
          nombre: null,
          precioVentaMenor: 4550,
          predeterminada: true,
          orden: 0,
        ),
      ],
    ),
  ]);

  testWidgets('shows the three inventory tabs without modifiers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
        ),
      ),
    );

    expect(find.text('ARTÍCULOS'), findsOneWidget);
    expect(find.text('CATEGORÍA'), findsOneWidget);
    expect(find.text('RECURSOS'), findsOneWidget);
    expect(find.text('MODIFICADORES'), findsNothing);
  });

  testWidgets('shows categories from the repository and the add button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
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
          productoRepository: productoRepository,
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

  testWidgets(
    'busca con debounce y conserva búsqueda y filtros al cambiar de pestaña',
    (tester) async {
      final repository = _FakeProductoRepository([
        ...productoRepository.articulos,
        const ArticuloListado(
          productoId: 'product-2',
          nombre: 'Té verde',
          activo: true,
          categoriaId: null,
          categoriaNombre: null,
          categoriaColor: null,
          variantePredeterminadaId: 'variant-2',
          precioPredeterminadoMenor: 3200,
          variantesActivas: [
            VarianteListado(
              varianteId: 'variant-2',
              nombre: null,
              precioVentaMenor: 3200,
              predeterminada: true,
              orden: 0,
            ),
          ],
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryManagementScreen(
            categoriaRepository: categoriaRepository,
            productoRepository: repository,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('open_article_search_button')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('article_search_field')),
        'Caf',
      );
      await tester.pump(const Duration(milliseconds: 199));

      expect(repository.queries.last.search, '');
      expect(find.text('Té verde'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(repository.queries.last.search, 'Caf');
      expect(find.text('Café'), findsOneWidget);
      expect(find.text('Té verde'), findsNothing);

      await tester.tap(find.byKey(const Key('open_article_filters_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('article_filter_category_category-1')),
      );
      await tester.tap(find.byKey(const Key('apply_article_filters_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CATEGORÍA'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ARTÍCULOS'));
      await tester.pumpAndSettle();

      final searchField = tester.widget<TextField>(
        find.byKey(const Key('article_search_field')),
      );
      expect(searchField.controller!.text, 'Caf');
      expect(
        find.bySemanticsLabel('Filtrar artículos, 1 filtro aplicado'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('close_article_search_button')));
      await tester.pump();
      expect(find.text('GESTIÓN DEL INVENTARIO'), findsOneWidget);
      expect(repository.queries.last.search, 'Caf');
      expect(repository.queries.last.categoryIds, {'category-1'});

      await tester.tap(find.byKey(const Key('open_article_search_button')));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('article_search_field')))
            .controller!
            .text,
        'Caf',
      );

      await tester.tap(find.byKey(const Key('clear_article_search_button')));
      await tester.pump();

      expect(repository.queries.last.search, '');
      expect(repository.queries.last.categoryIds, {'category-1'});
    },
  );

  testWidgets('abre el menú completo y crea una categoría con color', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Agregar'));
    await tester.pumpAndSettle();

    expect(find.text('Añadir artículo'), findsOneWidget);
    expect(find.text('Añadir categoría'), findsOneWidget);
    expect(find.text('Añadir modificador'), findsOneWidget);
    expect(find.text('Añadir recurso de inventario'), findsOneWidget);
    expect(find.text('Edición masiva'), findsOneWidget);

    await tester.tap(find.text('Añadir categoría'));
    await tester.pumpAndSettle();

    expect(find.text('CATEGORÍA'), findsOneWidget);
    expect(find.text('Cargar desde la galería'), findsNothing);
    expect(find.text('Tomar foto'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('category_name_field')),
      ' Bebidas calientes ',
    );
    await tester.tap(find.byKey(const Key('edit_category_color_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category_color_amber')));
    await tester.pump();
    await tester.tap(find.text('ACEPTAR'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_category_button')));
    await tester.pumpAndSettle();

    expect(commandService.command, isNotNull);
    expect(commandService.command!.nombre, ' Bebidas calientes ');
    expect(commandService.command!.color, ColorCategoria.amber);
  });

  testWidgets('abre y guarda el alta sencilla de artículo', (tester) async {
    final productService = _FakeProductoCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
          productoCommandService: productService,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Agregar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir artículo'));
    await tester.pumpAndSettle();

    expect(find.text('AÑADIR ARTÍCULO'), findsOneWidget);
    expect(find.text('Avance'), findsNothing);
    expect(find.text('Cambiar imagen'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('article_name_field')),
      ' Café americano ',
    );
    await tester.enterText(
      find.byKey(const Key('article_price_field')),
      '45.50',
    );
    await tester.tap(find.byKey(const Key('article_category_field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bebidas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_article_button')));
    await tester.pumpAndSettle();

    expect(productService.command?.nombre, ' Café americano ');
    expect(productService.command?.categoriaId, 'category-1');
    expect(productService.command?.precioVenta, '45.50');
    expect(find.text('Artículo guardado.'), findsOneWidget);
  });

  testWidgets('abre la categoría con un toque y guarda sus cambios', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );

    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(InventoryCategoryCard));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(
      find.byKey(const Key('category_name_field')),
    );
    expect(field.controller!.text, 'Bebidas');

    await tester.enterText(
      find.byKey(const Key('category_name_field')),
      'Bebidas premium',
    );
    await tester.tap(find.byKey(const Key('save_category_button')));
    await tester.pumpAndSettle();

    expect(commandService.editCommand, isNotNull);
    expect(commandService.editCommand!.categoriaId, 'category-1');
    expect(commandService.editCommand!.nombre, 'Bebidas premium');
    expect(commandService.editCommand!.color, ColorCategoria.blue);
  });

  testWidgets('las flechas mueven categorías y respetan los límites', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    final repository = _FakeCategoriaRepository(const [
      categoria,
      Categoria(
        id: 'category-2',
        nombre: 'Comidas',
        color: ColorCategoria.amber,
        orden: 1,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: repository,
          productoRepository: productoRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );

    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();

    final firstCard = find.byKey(const ValueKey('category-1'));
    final secondCard = find.byKey(const ValueKey('category-2'));
    final firstUp = find.descendant(
      of: firstCard,
      matching: find.byKey(const Key('move_category_up_button')),
    );
    final secondUp = find.descendant(
      of: secondCard,
      matching: find.byKey(const Key('move_category_up_button')),
    );
    final secondDown = find.descendant(
      of: secondCard,
      matching: find.byKey(const Key('move_category_down_button')),
    );

    expect(tester.widget<IconButton>(firstUp).onPressed, isNull);
    expect(tester.widget<IconButton>(secondDown).onPressed, isNull);

    await tester.tap(secondUp);
    await tester.pump();

    expect(commandService.moveCommand?.categoriaId, 'category-2');
    expect(commandService.moveCommand?.direccion.name, 'arriba');
  });

  testWidgets('ofrece resoluciones y usa singular cuando hay un artículo', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('tiene 1 artículo vinculado.'), findsOneWidget);
    expect(find.text('Mover a otra categoría'), findsOneWidget);
    expect(find.text('Dejar sin categoría'), findsOneWidget);
    expect(find.text('Eliminar todos'), findsNothing);
    expect(commandService.deleteCommand, isNull);
    await tester.tap(
      find.byKey(const Key('cancel_delete_category_with_products_button')),
    );
    await tester.pumpAndSettle();
    expect(commandService.deleteCommand, isNull);
  });

  testWidgets('mueve artículos por ID y elimina después de confirmar', (
    tester,
  ) async {
    const destination = Categoria(
      id: 'category-2',
      nombre: 'Comida',
      color: ColorCategoria.amber,
      orden: 1,
    );
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: _FakeCategoriaRepository([
            categoria,
            destination,
          ]),
          productoRepository: productoRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move_category_products_option')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('destination_category_option_category-1')),
      findsNothing,
    );
    final continueButton = tester.widget<FilledButton>(
      find.byKey(const Key('confirm_destination_category_button')),
    );
    expect(continueButton.onPressed, isNull);
    await tester.tap(
      find.byKey(const Key('destination_category_option_category-2')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('confirm_destination_category_button')),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Se moverá 1 artículo de “Bebidas” a “Comida”'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('confirm_move_and_delete_category_button')),
    );
    await tester.pumpAndSettle();

    expect(
      commandService.deleteCommand?.resolucion,
      ResolucionProductosCategoria.move,
    );
    expect(commandService.deleteCommand?.categoriaDestinoId, 'category-2');
    expect(commandService.deleteCommand?.productoIdsConfirmados, ['product-1']);
    expect(find.text('Categoría eliminada.'), findsOneWidget);
  });

  testWidgets('deja artículos sin categoría y elimina', (tester) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('uncategorize_category_products_option')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('quedará sin categoría'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('confirm_uncategorize_and_delete_category_button')),
    );
    await tester.pumpAndSettle();

    expect(
      commandService.deleteCommand?.resolucion,
      ResolucionProductosCategoria.uncategorize,
    );
    expect(commandService.deleteCommand?.categoriaDestinoId, isNull);
    expect(commandService.deleteCommand?.productoIdsConfirmados, ['product-1']);
  });

  testWidgets('sin destinos permite regresar y conservar sin categoría', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('move_category_products_option')));
    await tester.pumpAndSettle();

    expect(find.text('No hay otra categoría disponible.'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('back_from_destination_picker_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dejar sin categoría'), findsOneWidget);
    expect(commandService.deleteCommand, isNull);
  });

  testWidgets('cancelar confirmación de resolución no genera comando', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: productoRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('uncategorize_category_products_option')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('cancel_category_product_resolution_button')),
    );
    await tester.pumpAndSettle();

    expect(commandService.deleteCommand, isNull);
  });

  testWidgets('confirma categoría vacía, elimina y muestra éxito', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: _FakeProductoRepository(const []),
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();

    expect(find.text('Eliminar categoría'), findsOneWidget);
    expect(
      find.text(
        '¿Quieres eliminar la categoría “Bebidas”? Esta acción no se puede deshacer.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm_delete_category_button')));
    await tester.pumpAndSettle();

    expect(commandService.deleteCommand?.categoriaId, 'category-1');
    expect(find.text('Categoría eliminada.'), findsOneWidget);
  });

  testWidgets('cancelar no genera evento de eliminación', (tester) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: _FakeProductoRepository(const []),
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel_delete_category_button')));
    await tester.pumpAndSettle();

    expect(commandService.deleteCommand, isNull);
  });

  testWidgets('muestra error recuperable si falla la eliminación', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService()
      ..deleteError = StateError('falló');
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: _FakeProductoRepository(const []),
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_delete_category_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('No se pudo eliminar la categoría. Inténtalo nuevamente.'),
      findsOneWidget,
    );
  });

  testWidgets('bloquea doble confirmación mientras elimina', (tester) async {
    final commandService = _FakeCategoriaCommandService()
      ..deleteCompleter = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: _FakeProductoRepository(const []),
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirm_delete_category_button'));
    await tester.tap(confirm);
    await tester.pump();
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pump();

    expect(commandService.deleteCalls, 1);
    commandService.deleteCompleter!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('un fallo de conteo no abre una ruta destructiva', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          productoRepository: _FakeProductoRepository(
            const [],
            countError: StateError('falló'),
          ),
          categoriaCommandService: commandService,
        ),
      ),
    );
    await tester.tap(find.text('CATEGORÍA'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_category_button')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No se pudo comprobar si la categoría tiene artículos vinculados.',
      ),
      findsOneWidget,
    );
    expect(commandService.deleteCommand, isNull);
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

class _FakeProductoRepository implements ProductoRepository {
  _FakeProductoRepository(this.articulos, {this.countError});

  final List<ArticuloListado> articulos;
  final Object? countError;
  final List<_ProductQuery> queries = [];

  @override
  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  ) async {
    if (countError != null) throw countError!;
    return articulos
        .where((articulo) => articulo.categoriaId == categoriaId)
        .map(
          (articulo) => ArticuloVinculadoCategoria(
            productoId: articulo.productoId,
            activo: articulo.activo,
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) {
    queries.add(
      _ProductQuery(search: busqueda, categoryIds: Set.of(categoriaIds)),
    );
    final normalizedSearch = busqueda.trim().toLowerCase();
    return Stream.value(
      articulos
          .where((article) {
            final matchesSearch =
                normalizedSearch.isEmpty ||
                article.nombre.toLowerCase().contains(normalizedSearch);
            final hasCategoryFilter =
                categoriaIds.isNotEmpty || incluirSinCategoria;
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

class _ProductQuery {
  const _ProductQuery({required this.search, required this.categoryIds});

  final String search;
  final Set<String> categoryIds;
}

class _FakeCategoriaCommandService implements CategoriaCommandService {
  CrearCategoriaCommand? command;
  EditarCategoriaCommand? editCommand;
  MoverCategoriaCommand? moveCommand;
  EliminarCategoriaCommand? deleteCommand;
  Object? deleteError;
  Completer<void>? deleteCompleter;
  int deleteCalls = 0;

  @override
  Future<void> eliminarCategoria(EliminarCategoriaCommand command) async {
    deleteCalls++;
    deleteCommand = command;
    if (deleteError != null) throw deleteError!;
    await deleteCompleter?.future;
  }

  @override
  Future<void> crearCategoria(CrearCategoriaCommand command) async {
    this.command = command;
  }

  @override
  Future<bool> editarCategoria(EditarCategoriaCommand command) async {
    editCommand = command;
    return true;
  }

  @override
  Future<bool> moverCategoria(MoverCategoriaCommand command) async {
    moveCommand = command;
    return true;
  }
}

class _FakeProductoCommandService implements ProductoCommandService {
  CrearArticuloCommand? command;

  @override
  Future<void> crearArticulo(CrearArticuloCommand command) async {
    this.command = command;
  }
}
