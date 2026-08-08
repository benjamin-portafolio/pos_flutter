import 'package:flutter/material.dart';

import '../../../../domain/articulos/articulo_listado.dart';
import '../../../../domain/repositories/categoria_repository.dart';
import '../../../../domain/repositories/producto_repository.dart';
import 'models/filtro_articulos.dart';
import 'widgets/article_filters_bottom_sheet.dart';
import 'widgets/inventory_article_card.dart';

class InventoryArticlesTab extends StatefulWidget {
  const InventoryArticlesTab({
    required this.productoRepository,
    required this.categoriaRepository,
    required this.busqueda,
    required this.onClearSearch,
    required this.onAddArticle,
    super.key,
  });

  final ProductoRepository productoRepository;
  final CategoriaRepository categoriaRepository;
  final String busqueda;
  final VoidCallback onClearSearch;
  final VoidCallback onAddArticle;

  @override
  State<InventoryArticlesTab> createState() => _InventoryArticlesTabState();
}

class _InventoryArticlesTabState extends State<InventoryArticlesTab>
    with AutomaticKeepAliveClientMixin {
  FiltroArticulos _appliedFilter = const FiltroArticulos();
  late Stream<List<ArticuloListado>> _articlesStream;

  @override
  void initState() {
    super.initState();
    _articlesStream = _watchArticles();
  }

  @override
  void didUpdateWidget(covariant InventoryArticlesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productoRepository != widget.productoRepository ||
        oldWidget.busqueda != widget.busqueda) {
      _articlesStream = _watchArticles();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      top: false,
      child: ColoredBox(
        key: const Key('inventory_articles_tab_view'),
        color: const Color(0xFFE6E6E6),
        child: Column(
          children: [
            _FilterBar(
              appliedFilter: _appliedFilter,
              onShowAll: _clearFilters,
              onOpenFilters: _openFilters,
            ),
            Expanded(
              child: StreamBuilder<List<ArticuloListado>>(
                stream: _articlesStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ArticleState(
                      message: 'No se pudieron cargar los artículos.',
                      icon: Icons.error_outline,
                      actions: [
                        FilledButton.icon(
                          key: const Key('retry_articles_button'),
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final articles = snapshot.data!;
                  if (articles.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 96),
                    itemCount: articles.length,
                    itemBuilder: (context, index) {
                      final article = articles[index];
                      return InventoryArticleCard(
                        key: ValueKey(article.productoId),
                        articulo: article,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  Widget _buildEmptyState() {
    final hasSearch = widget.busqueda.trim().isNotEmpty;
    if (!hasSearch && _appliedFilter.isEmpty) {
      return _ArticleState(
        message: 'No hay artículos.',
        icon: Icons.inventory_2_outlined,
        actions: [
          FilledButton.icon(
            key: const Key('add_article_from_empty_state_button'),
            onPressed: widget.onAddArticle,
            icon: const Icon(Icons.add),
            label: const Text('Añadir artículo'),
          ),
        ],
      );
    }

    return _ArticleState(
      message: 'No se encontraron artículos.',
      icon: Icons.search_off,
      actions: [
        if (hasSearch)
          TextButton(
            key: const Key('clear_search_from_empty_state_button'),
            onPressed: widget.onClearSearch,
            child: const Text('Limpiar búsqueda'),
          ),
        if (!_appliedFilter.isEmpty)
          TextButton(
            key: const Key('clear_filters_from_empty_state_button'),
            onPressed: _clearFilters,
            child: const Text('Limpiar filtros'),
          ),
      ],
    );
  }

  Stream<List<ArticuloListado>> _watchArticles() {
    return widget.productoRepository.watchArticulos(
      busqueda: widget.busqueda,
      categoriaIds: _appliedFilter.categoryIds,
      incluirSinCategoria: _appliedFilter.includeUncategorized,
    );
  }

  Future<void> _openFilters() async {
    final result = await ArticleFiltersBottomSheet.show(
      context: context,
      categoriaRepository: widget.categoriaRepository,
      appliedFilter: _appliedFilter,
    );
    if (result == null || result == _appliedFilter || !mounted) return;
    setState(() {
      _appliedFilter = result;
      _articlesStream = _watchArticles();
    });
  }

  void _clearFilters() {
    if (_appliedFilter.isEmpty) return;
    setState(() {
      _appliedFilter = const FiltroArticulos();
      _articlesStream = _watchArticles();
    });
  }

  void _retry() {
    setState(() => _articlesStream = _watchArticles());
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.appliedFilter,
    required this.onShowAll,
    required this.onOpenFilters,
  });

  final FiltroArticulos appliedFilter;
  final VoidCallback onShowAll;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final count = appliedFilter.appliedCount;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            ChoiceChip(
              key: const Key('all_articles_filter_chip'),
              label: const Text('Todos'),
              selected: appliedFilter.isEmpty,
              onSelected: (_) => onShowAll(),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              onTap: onOpenFilters,
              label: count == 0
                  ? 'Filtrar artículos'
                  : count == 1
                  ? 'Filtrar artículos, 1 filtro aplicado'
                  : 'Filtrar artículos, $count filtros aplicados',
              child: ExcludeSemantics(
                child: OutlinedButton.icon(
                  key: const Key('open_article_filters_button'),
                  onPressed: onOpenFilters,
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.filter_list),
                  ),
                  label: const Text('Filtros'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleState extends StatelessWidget {
  const _ArticleState({
    required this.message,
    required this.icon,
    required this.actions,
  });

  final String message;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
