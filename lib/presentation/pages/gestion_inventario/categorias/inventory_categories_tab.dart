import 'package:flutter/material.dart';

import '../../../../domain/categorias/categoria.dart';
import '../../../../domain/categorias/direccion_movimiento_categoria.dart';
import '../../../../domain/repositories/categoria_repository.dart';
import '../../../../domain/repositories/margen_promedio_repository.dart';
import 'category_color_palette.dart';
import 'widgets/inventory_category_card.dart';

class InventoryCategoriesTab extends StatefulWidget {
  const InventoryCategoriesTab({
    required this.categoriaRepository,
    required this.onEditCategory,
    required this.onMoveCategory,
    required this.onDeleteCategory,
    this.margenPromedioRepository,
    super.key,
  });

  final CategoriaRepository categoriaRepository;
  final MargenPromedioRepository? margenPromedioRepository;
  final ValueChanged<Categoria> onEditCategory;
  final void Function(Categoria, DireccionMovimientoCategoria) onMoveCategory;
  final ValueChanged<Categoria> onDeleteCategory;

  @override
  State<InventoryCategoriesTab> createState() => _InventoryCategoriesTabState();
}

class _InventoryCategoriesTabState extends State<InventoryCategoriesTab> {
  late Stream<List<Categoria>> _categorias;
  late Stream<Map<String, double>> _margenes;

  @override
  void initState() {
    super.initState();
    _bindStreams();
  }

  @override
  void didUpdateWidget(InventoryCategoriesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categoriaRepository != widget.categoriaRepository ||
        oldWidget.margenPromedioRepository != widget.margenPromedioRepository) {
      _bindStreams();
    }
  }

  void _bindStreams() {
    _categorias = widget.categoriaRepository.watchCategorias();
    _margenes =
        widget.margenPromedioRepository?.watchMargenPromedioPorCategoria() ??
        Stream.value(const <String, double>{});
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('inventory_categories_tab_view'),
      color: const Color(0xFFE6E6E6),
      child: StreamBuilder<List<Categoria>>(
        stream: _categorias,
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
          return StreamBuilder<Map<String, double>>(
            stream: _margenes,
            builder: (context, margenSnapshot) {
              final margenes = margenSnapshot.data ?? const <String, double>{};
              final cargando =
                  widget.margenPromedioRepository != null &&
                  !margenSnapshot.hasData &&
                  !margenSnapshot.hasError;
              final error = margenSnapshot.hasError;
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                itemCount: categorias.length,
                itemBuilder: (context, index) {
                  final categoria = categorias[index];
                  return InventoryCategoryCard(
                    key: ValueKey(categoria.id),
                    name: categoria.nombre,
                    color: CategoryColorPalette.resolve(categoria.color),
                    margenPromedioPorcentaje: margenes[categoria.id],
                    margenCargando: cargando,
                    margenError: error,
                    onTap: () => widget.onEditCategory(categoria),
                    onDeleteCategory: () => widget.onDeleteCategory(categoria),
                    onMoveUp: index == 0
                        ? null
                        : () => widget.onMoveCategory(
                            categoria,
                            DireccionMovimientoCategoria.arriba,
                          ),
                    onMoveDown: index == categorias.length - 1
                        ? null
                        : () => widget.onMoveCategory(
                            categoria,
                            DireccionMovimientoCategoria.abajo,
                          ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
