import 'package:flutter/material.dart';

import '../../../../domain/categorias/categoria.dart';
import '../../../../domain/categorias/color_categoria.dart';
import '../../../../domain/repositories/categoria_repository.dart';
import 'widgets/inventory_category_card.dart';

class InventoryCategoriesTab extends StatelessWidget {
  const InventoryCategoriesTab({required this.categoriaRepository, super.key});

  final CategoriaRepository categoriaRepository;

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
                color: _categoryColor(context, categoria.color),
              );
            },
          );
        },
      ),
    );
  }

  Color _categoryColor(BuildContext context, ColorCategoria color) {
    final darkTheme = Theme.of(context).brightness == Brightness.dark;

    return switch (color) {
      ColorCategoria.neutral =>
        darkTheme ? const Color(0xFF9E9E9E) : const Color(0xFF616161),
      ColorCategoria.red =>
        darkTheme ? const Color(0xFFEF5350) : const Color(0xFFD32F2F),
      ColorCategoria.orange =>
        darkTheme ? const Color(0xFFFFA726) : const Color(0xFFF57C00),
      ColorCategoria.amber =>
        darkTheme ? const Color(0xFFFFCA28) : const Color(0xFFFFA000),
      ColorCategoria.green =>
        darkTheme ? const Color(0xFF66BB6A) : const Color(0xFF388E3C),
      ColorCategoria.teal =>
        darkTheme ? const Color(0xFF26A69A) : const Color(0xFF00796B),
      ColorCategoria.blue =>
        darkTheme ? const Color(0xFF42A5F5) : const Color(0xFF1976D2),
      ColorCategoria.indigo =>
        darkTheme ? const Color(0xFF5C6BC0) : const Color(0xFF303F9F),
      ColorCategoria.purple =>
        darkTheme ? const Color(0xFFAB47BC) : const Color(0xFF7B1FA2),
      ColorCategoria.pink =>
        darkTheme ? const Color(0xFFEC407A) : const Color(0xFFC2185B),
    };
  }
}
