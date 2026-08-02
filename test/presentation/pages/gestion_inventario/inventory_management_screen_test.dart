import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/categoria_command_service.dart';
import 'package:pos_flutter/application/commands/crear_categoria_command.dart';
import 'package:pos_flutter/application/commands/editar_categoria_command.dart';
import 'package:pos_flutter/application/commands/mover_categoria_command.dart';
import 'package:pos_flutter/domain/categorias/categoria.dart';
import 'package:pos_flutter/domain/categorias/color_categoria.dart';
import 'package:pos_flutter/domain/repositories/categoria_repository.dart';
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

  testWidgets('shows the three inventory tabs without modifiers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
        ),
      ),
    );

    expect(find.text('ARTÍCULOS'), findsOneWidget);
    expect(find.text('CATEGORÍA'), findsOneWidget);
    expect(find.text('INGREDIENTES'), findsOneWidget);
    expect(find.text('MODIFICADORES'), findsNothing);
  });

  testWidgets('shows categories from the repository and the add button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
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

  testWidgets('abre el menú completo y crea una categoría con color', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
          categoriaCommandService: commandService,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Agregar'));
    await tester.pumpAndSettle();

    expect(find.text('Añadir artículo'), findsOneWidget);
    expect(find.text('Añadir categoría'), findsOneWidget);
    expect(find.text('Añadir modificador'), findsOneWidget);
    expect(find.text('Agregar ingrediente'), findsOneWidget);
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

  testWidgets('abre la categoría con un toque y guarda sus cambios', (
    tester,
  ) async {
    final commandService = _FakeCategoriaCommandService();
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: categoriaRepository,
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
}

class _FakeCategoriaRepository implements CategoriaRepository {
  _FakeCategoriaRepository(this.categorias);

  final List<Categoria> categorias;

  @override
  Future<List<Categoria>> obtenerCategorias() async => categorias;

  @override
  Stream<List<Categoria>> watchCategorias() => Stream.value(categorias);
}

class _FakeCategoriaCommandService implements CategoriaCommandService {
  CrearCategoriaCommand? command;
  EditarCategoriaCommand? editCommand;
  MoverCategoriaCommand? moveCommand;

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
