import 'package:flutter/material.dart';

import '../../../../domain/categorias/categoria.dart';
import '../../../../domain/categorias/direccion_movimiento_categoria.dart';
import '../../../../domain/repositories/categoria_repository.dart';
import 'category_color_palette.dart';
import 'widgets/inventory_category_card.dart';

class InventoryCategoriesTab extends StatelessWidget {
  const InventoryCategoriesTab({
    required this.categoriaRepository,
    required this.onEditCategory,
    required this.onMoveCategory,
    required this.onDeleteCategory,
    super.key,
  });

  final CategoriaRepository categoriaRepository;
  final ValueChanged<Categoria> onEditCategory;
  final void Function(Categoria, DireccionMovimientoCategoria) onMoveCategory;
  final ValueChanged<Categoria> onDeleteCategory;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('inventory_categories_tab_view'),
      color: const Color(0xFFE6E6E6),
      child: StreamBuilder<List<Categoria>>(
        stream: categoriaRepository.watchCategorias(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text('No se pudieron cargar las categorías.'),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final categorias = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: categorias.length,
            itemBuilder: (context, index) {
              final categoria = categorias[index];
              return InventoryCategoryCard(
                key: ValueKey(categoria.id),
                name: categoria.nombre,
                color: CategoryColorPalette.resolve(categoria.color),
                onTap: () => onEditCategory(categoria),
                onDeleteCategory: () => onDeleteCategory(categoria),
                onMoveUp: index == 0
                    ? null
                    : () => onMoveCategory(
                        categoria,
                        DireccionMovimientoCategoria.arriba,
                      ),
                onMoveDown: index == categorias.length - 1
                    ? null
                    : () => onMoveCategory(
                        categoria,
                        DireccionMovimientoCategoria.abajo,
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
