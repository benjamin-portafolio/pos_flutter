import 'package:flutter/material.dart';

import '../../../application/commands/categoria_command_service.dart';
import '../../../application/commands/crear_categoria_command.dart';
import '../../../application/commands/editar_categoria_command.dart';
import '../../../application/commands/mover_categoria_command.dart';
import '../../../application/commands/crear_articulo_command.dart';
import '../../../application/commands/producto_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/categorias/categoria.dart';
import '../../../domain/categorias/direccion_movimiento_categoria.dart';
import '../../../domain/repositories/categoria_repository.dart';
import 'categorias/category_form_screen.dart';
import 'categorias/inventory_categories_tab.dart';
import 'categorias/models/categoria_form_result.dart';
import 'articulos/article_form_screen.dart';
import 'articulos/models/articulo_form_result.dart';
import 'widgets/inventory_add_options_bottom_sheet.dart';

class InventoryManagementScreen extends StatelessWidget {
  const InventoryManagementScreen({
    this.categoriaRepository,
    this.categoriaCommandService,
    this.productoCommandService,
    super.key,
  });

  final CategoriaRepository? categoriaRepository;
  final CategoriaCommandService? categoriaCommandService;
  final ProductoCommandService? productoCommandService;

  @override
  Widget build(BuildContext context) {
    final categories = categoriaRepository ?? getIt<CategoriaRepository>();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GESTIÓN DEL INVENTARIO'),
          centerTitle: true,
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search),
              tooltip: 'Buscar',
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'ARTÍCULOS'),
              Tab(text: 'CATEGORÍA'),
              Tab(text: 'INGREDIENTES'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const SizedBox.expand(key: Key('inventory_articles_tab_view')),
            InventoryCategoriesTab(
              categoriaRepository: categories,
              onEditCategory: (categoria) =>
                  _openCategoryForm(context, categoria: categoria),
              onMoveCategory: (categoria, direccion) =>
                  _moveCategory(context, categoria, direccion),
            ),
            const SizedBox.expand(key: Key('inventory_ingredients_tab_view')),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddOptions(context),
          tooltip: 'Agregar',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    InventoryAddOptionsBottomSheet.show(
      context: context,
      onAddArticle: () => _openArticleForm(context),
      onAddCategory: () => _openCategoryForm(context),
    );
  }

  Future<void> _openArticleForm(BuildContext context) async {
    final categories = categoriaRepository ?? getIt<CategoriaRepository>();
    try {
      final categorias = await categories.obtenerCategorias();
      if (!context.mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ArticleFormScreen(
            categorias: categorias,
            onSave: (result) => _createArticle(result),
          ),
        ),
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Artículo guardado.')));
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el alta de artículo.')),
      );
    }
  }

  Future<void> _createArticle(ArticuloFormResult result) {
    final service = productoCommandService ?? getIt<ProductoCommandService>();
    return service.crearArticulo(
      CrearArticuloCommand(
        nombre: result.nombre,
        categoriaId: result.categoriaId,
        precioVenta: result.precioVenta,
      ),
    );
  }

  Future<void> _openCategoryForm(
    BuildContext context, {
    Categoria? categoria,
  }) async {
    final result = await Navigator.of(context).push<CategoriaFormResult>(
      MaterialPageRoute(
        builder: (_) => CategoryFormScreen(
          initialValue: categoria == null
              ? null
              : CategoriaFormResult(
                  nombre: categoria.nombre,
                  color: categoria.color,
                ),
        ),
      ),
    );
    if (result == null || !context.mounted) return;

    try {
      final service =
          categoriaCommandService ?? getIt<CategoriaCommandService>();
      if (categoria == null) {
        await service.crearCategoria(
          CrearCategoriaCommand(nombre: result.nombre, color: result.color),
        );
      } else {
        await service.editarCategoria(
          EditarCategoriaCommand(
            categoriaId: categoria.id,
            nombre: result.nombre,
            color: result.color,
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar la categoría.')),
      );
    }
  }

  Future<void> _moveCategory(
    BuildContext context,
    Categoria categoria,
    DireccionMovimientoCategoria direccion,
  ) async {
    try {
      final service =
          categoriaCommandService ?? getIt<CategoriaCommandService>();
      await service.moverCategoria(
        MoverCategoriaCommand(categoriaId: categoria.id, direccion: direccion),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo mover la categoría.')),
      );
    }
  }
}
