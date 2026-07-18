import 'package:flutter/material.dart';

import '../../../core/di/injection.dart';
import '../../../domain/repositories/categoria_repository.dart';
import 'categorias/inventory_categories_tab.dart';

class InventoryManagementScreen extends StatelessWidget {
  const InventoryManagementScreen({this.categoriaRepository, super.key});

  final CategoriaRepository? categoriaRepository;

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
            InventoryCategoriesTab(categoriaRepository: categories),
            const SizedBox.expand(key: Key('inventory_ingredients_tab_view')),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          tooltip: 'Agregar',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
