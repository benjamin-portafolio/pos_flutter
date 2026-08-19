import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../domain/inventario/inventory_resource_filter.dart';
import '../../../../domain/inventario/recurso_inventario_listado.dart';
import '../../../../domain/repositories/recurso_inventario_repository.dart';
import 'widgets/inventory_resource_card.dart';

class InventoryResourcesTab extends StatefulWidget {
  const InventoryResourcesTab({required this.repository, super.key});

  final RecursoInventarioRepository repository;

  @override
  State<InventoryResourcesTab> createState() => _InventoryResourcesTabState();
}

class _InventoryResourcesTabState extends State<InventoryResourcesTab> {
  static const _debounce = Duration(milliseconds: 200);

  final _searchController = TextEditingController();
  Timer? _searchTimer;
  String _search = '';
  InventoryResourceFilter _filter = InventoryResourceFilter.all;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(
            'Recursos de inventario',
            key: const Key('inventory_resources_title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            key: const Key('inventory_resource_search_field'),
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar recursos por nombre',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: () {
                        _searchController.clear();
                        _applySearch('');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() {});
              _searchTimer?.cancel();
              _searchTimer = Timer(_debounce, () => _applySearch(value));
            },
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: InventoryResourceFilter.values
                .map(
                  (filter) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      key: Key('inventory_filter_${filter.name}'),
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: StreamBuilder<List<RecursoInventarioListado>>(
            stream: widget.repository.watchRecursos(
              busqueda: _search,
              filtro: _filter,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('No se pudieron cargar los recursos.'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final resources = snapshot.data!;
              if (resources.isEmpty) {
                return Center(
                  child: Text(
                    _search.isEmpty && _filter == InventoryResourceFilter.all
                        ? 'Aún no hay recursos de inventario.'
                        : 'No hay recursos que coincidan.',
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: resources.length,
                itemBuilder: (_, index) =>
                    InventoryResourceCard(resource: resources[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  void _applySearch(String value) {
    if (!mounted) return;
    setState(() => _search = value.trim());
  }
}
