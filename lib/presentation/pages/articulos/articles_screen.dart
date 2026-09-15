import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../domain/articulos/articulo_listado.dart';
import '../../../domain/categorias/categoria.dart';
import '../../../domain/repositories/categoria_repository.dart';
import '../../../domain/repositories/producto_repository.dart';
import '../../widgets/article_search_bar.dart';
import '../gestion_inventario/categorias/category_color_palette.dart';

class ArticlesScreen extends StatefulWidget {
  const ArticlesScreen({
    this.categoriaRepository,
    this.productoRepository,
    this.onOpenCaja,
    super.key,
  });

  final VoidCallback? onOpenCaja;
  final CategoriaRepository? categoriaRepository;
  final ProductoRepository? productoRepository;

  @override
  State<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends State<ArticlesScreen> {
  late final Stream<List<Categoria>> _categories =
      (widget.categoriaRepository ?? getIt<CategoriaRepository>())
          .watchCategorias();
  late final Stream<Map<String, int>> _productCounts =
      (widget.productoRepository ?? getIt<ProductoRepository>())
          .watchArticulos()
          .map(_countProducts);

  // Selección visual de esta pantalla; no persiste ni genera eventos.
  final Set<String> _selectedCategories = {};

  Map<String, int> _countProducts(List<ArticuloListado> articles) {
    final counts = <String, int>{};
    for (final article in articles) {
      final categoryId = article.categoriaId;
      if (categoryId != null) {
        counts.update(categoryId, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          ArticleSearchBar(
            productoRepository: widget.productoRepository,
            onOpenCaja: widget.onOpenCaja,
          ),
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFE6E6E6),
              child: StreamBuilder<List<Categoria>>(
                stream: _categories,
                builder: (context, categoriesSnapshot) {
                  if (categoriesSnapshot.hasError) {
                    return const Center(
                      child: Text('No se pudieron cargar las categorías.'),
                    );
                  }
                  if (!categoriesSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final categories = categoriesSnapshot.data!;
                  if (categories.isEmpty) {
                    return const Center(child: Text('No hay categorías.'));
                  }
                  return StreamBuilder<Map<String, int>>(
                    stream: _productCounts,
                    builder: (context, countsSnapshot) {
                      if (countsSnapshot.hasError) {
                        return const Center(
                          child: Text('No se pudieron cargar los artículos.'),
                        );
                      }
                      if (!countsSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        itemCount: categories.length,
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          return _ArticleCategoryCard(
                            key: ValueKey(category.id),
                            category: category,
                            productCount:
                                countsSnapshot.data![category.id] ?? 0,
                            selected: _selectedCategories.contains(category.id),
                            onChanged: (selected) => setState(() {
                              if (selected == true) {
                                _selectedCategories.add(category.id);
                              } else {
                                _selectedCategories.remove(category.id);
                              }
                            }),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArticleCategoryCard extends StatelessWidget {
  const _ArticleCategoryCard({
    required this.category,
    required this.productCount,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final Categoria category;
  final int productCount;
  final bool selected;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Card(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Row(
          children: [
            Icon(
              Icons.label,
              color: CategoryColorPalette.resolve(category.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${category.nombre} ($productCount)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Checkbox(
              value: selected,
              onChanged: onChanged,
              semanticLabel: 'Seleccionar categoría ${category.nombre}',
            ),
            const SizedBox(width: 8),
            Icon(Icons.arrow_drop_down, color: primaryColor, size: 32),
          ],
        ),
      ),
    );
  }
}
