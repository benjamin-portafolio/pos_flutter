import 'package:flutter/material.dart';

import '../../../../../domain/categorias/categoria.dart';
import '../../../../../domain/repositories/categoria_repository.dart';
import '../../categorias/category_color_palette.dart';
import '../models/filtro_articulos.dart';

class ArticleFiltersBottomSheet extends StatefulWidget {
  const ArticleFiltersBottomSheet({
    required this.categoriaRepository,
    required this.appliedFilter,
    super.key,
  });

  final CategoriaRepository categoriaRepository;
  final FiltroArticulos appliedFilter;

  static Future<FiltroArticulos?> show({
    required BuildContext context,
    required CategoriaRepository categoriaRepository,
    required FiltroArticulos appliedFilter,
  }) {
    return showModalBottomSheet<FiltroArticulos>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ArticleFiltersBottomSheet(
        categoriaRepository: categoriaRepository,
        appliedFilter: appliedFilter,
      ),
    );
  }

  @override
  State<ArticleFiltersBottomSheet> createState() =>
      _ArticleFiltersBottomSheetState();
}

class _ArticleFiltersBottomSheetState extends State<ArticleFiltersBottomSheet> {
  late FiltroArticulos _draft;
  late Stream<List<Categoria>> _categoriesStream;

  @override
  void initState() {
    super.initState();
    _draft = FiltroArticulos(
      categoryIds: Set.unmodifiable(widget.appliedFilter.categoryIds),
      includeUncategorized: widget.appliedFilter.includeUncategorized,
    );
    _categoriesStream = widget.categoriaRepository.watchCategorias();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      key: const Key('article_filters_bottom_sheet'),
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filtrar artículos',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton.icon(
                  key: const Key('close_article_filters_button'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Categorías',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<Categoria>>(
                    stream: _categoriesStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('No se pudieron cargar las categorías.'),
                            TextButton(
                              onPressed: _retryCategories,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final categories = snapshot.data!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (categories.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: Text('No hay categorías.'),
                            )
                          else
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: categories
                                  .map(
                                    (category) => FilterChip(
                                      key: ValueKey(
                                        'article_filter_category_'
                                        '${category.id}',
                                      ),
                                      label: Text(category.nombre),
                                      avatar: CircleAvatar(
                                        backgroundColor:
                                            CategoryColorPalette.resolve(
                                              category.color,
                                            ),
                                      ),
                                      selectedColor:
                                          CategoryColorPalette.resolve(
                                            category.color,
                                          ).withValues(alpha: 0.22),
                                      selected: _draft.categoryIds.contains(
                                        category.id,
                                      ),
                                      showCheckmark: true,
                                      onSelected: (selected) => setState(
                                        () => _draft = _draft.withCategory(
                                          category.id,
                                          selected: selected,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          const SizedBox(height: 8),
                          FilterChip(
                            key: const Key('article_filter_without_category'),
                            label: const Text('Sin categoría'),
                            selected: _draft.includeUncategorized,
                            showCheckmark: true,
                            onSelected: (selected) => setState(
                              () => _draft = _draft.withUncategorized(
                                selected: selected,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: const Key('reset_article_filters_button'),
                      onPressed: () =>
                          setState(() => _draft = const FiltroArticulos()),
                      child: const Text('Restablecer'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const Key('apply_article_filters_button'),
                      onPressed: () => Navigator.of(context).pop(_draft),
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _retryCategories() {
    setState(
      () => _categoriesStream = widget.categoriaRepository.watchCategorias(),
    );
  }
}
