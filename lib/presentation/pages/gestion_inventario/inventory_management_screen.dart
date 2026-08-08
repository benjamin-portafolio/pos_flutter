import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/commands/categoria_command_service.dart';
import '../../../application/commands/crear_articulo_command.dart';
import '../../../application/commands/crear_categoria_command.dart';
import '../../../application/commands/editar_categoria_command.dart';
import '../../../application/commands/mover_categoria_command.dart';
import '../../../application/commands/producto_command_service.dart';
import '../../../core/di/injection.dart';
import '../../../domain/categorias/categoria.dart';
import '../../../domain/categorias/direccion_movimiento_categoria.dart';
import '../../../domain/repositories/categoria_repository.dart';
import '../../../domain/repositories/producto_repository.dart';
import 'articulos/article_form_screen.dart';
import 'articulos/inventory_articles_tab.dart';
import 'articulos/models/articulo_form_result.dart';
import 'categorias/category_form_screen.dart';
import 'categorias/inventory_categories_tab.dart';
import 'categorias/models/categoria_form_result.dart';
import 'widgets/inventory_add_options_bottom_sheet.dart';

class InventoryManagementScreen extends StatelessWidget {
  const InventoryManagementScreen({
    this.categoriaRepository,
    this.productoRepository,
    this.categoriaCommandService,
    this.productoCommandService,
    super.key,
  });

  final CategoriaRepository? categoriaRepository;
  final ProductoRepository? productoRepository;
  final CategoriaCommandService? categoriaCommandService;
  final ProductoCommandService? productoCommandService;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: _InventoryManagementBody(
        categoriaRepository:
            categoriaRepository ?? getIt<CategoriaRepository>(),
        productoRepository: productoRepository ?? getIt<ProductoRepository>(),
        categoriaCommandService: categoriaCommandService,
        productoCommandService: productoCommandService,
      ),
    );
  }
}

class _InventoryManagementBody extends StatefulWidget {
  const _InventoryManagementBody({
    required this.categoriaRepository,
    required this.productoRepository,
    required this.categoriaCommandService,
    required this.productoCommandService,
  });

  final CategoriaRepository categoriaRepository;
  final ProductoRepository productoRepository;
  final CategoriaCommandService? categoriaCommandService;
  final ProductoCommandService? productoCommandService;

  @override
  State<_InventoryManagementBody> createState() =>
      _InventoryManagementBodyState();
}

class _InventoryManagementBodyState extends State<_InventoryManagementBody> {
  static const _searchDebounce = Duration(milliseconds: 200);

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  TabController? _tabController;
  Timer? _searchTimer;
  int _selectedTab = 0;
  bool _searchOpen = false;
  String _appliedSearch = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (_tabController == controller) return;
    _tabController?.removeListener(_handleTabChange);
    _tabController = controller..addListener(_handleTabChange);
    _selectedTab = controller.index;
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _tabController?.removeListener(_handleTabChange);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showingSearch = _selectedTab == 0 && _searchOpen;
    return Scaffold(
      appBar: AppBar(
        title: showingSearch ? _buildSearchField() : _buildTitle(),
        centerTitle: true,
        actions: _buildAppBarActions(showingSearch),
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
          InventoryArticlesTab(
            productoRepository: widget.productoRepository,
            categoriaRepository: widget.categoriaRepository,
            busqueda: _appliedSearch,
            onClearSearch: _clearSearch,
            onAddArticle: () => _openArticleForm(context),
          ),
          InventoryCategoriesTab(
            categoriaRepository: widget.categoriaRepository,
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
    );
  }

  Widget _buildTitle() {
    return const Text('GESTIÓN DEL INVENTARIO');
  }

  Widget _buildSearchField() {
    return TextField(
      key: const Key('article_search_field'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: 'Buscar artículos',
        border: InputBorder.none,
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchController,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              key: const Key('clear_article_search_button'),
              onPressed: _clearSearch,
              tooltip: 'Limpiar búsqueda',
              icon: const Icon(Icons.clear),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildAppBarActions(bool showingSearch) {
    if (_selectedTab != 0) return const [];
    if (showingSearch) {
      return [
        IconButton(
          key: const Key('close_article_search_button'),
          onPressed: _closeSearch,
          tooltip: 'Cerrar búsqueda',
          icon: const Icon(Icons.close),
        ),
      ];
    }
    return [
      IconButton(
        key: const Key('open_article_search_button'),
        onPressed: _openSearch,
        tooltip: 'Buscar',
        icon: const Icon(Icons.search),
      ),
    ];
  }

  void _handleTabChange() {
    final controller = _tabController;
    if (controller == null || controller.index == _selectedTab || !mounted) {
      return;
    }
    setState(() => _selectedTab = controller.index);
    if (_selectedTab != 0) {
      _searchFocusNode.unfocus();
    } else if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    setState(() => _searchOpen = false);
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted || value == _appliedSearch) return;
      setState(() => _appliedSearch = value);
    });
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    _searchController.clear();
    if (_appliedSearch.isEmpty) return;
    setState(() => _appliedSearch = '');
  }

  void _showAddOptions(BuildContext context) {
    InventoryAddOptionsBottomSheet.show(
      context: context,
      onAddArticle: () => _openArticleForm(context),
      onAddCategory: () => _openCategoryForm(context),
    );
  }

  Future<void> _openArticleForm(BuildContext context) async {
    try {
      final categorias = await widget.categoriaRepository.obtenerCategorias();
      if (!context.mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              ArticleFormScreen(categorias: categorias, onSave: _createArticle),
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
    final service =
        widget.productoCommandService ?? getIt<ProductoCommandService>();
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
          widget.categoriaCommandService ?? getIt<CategoriaCommandService>();
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
          widget.categoriaCommandService ?? getIt<CategoriaCommandService>();
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
