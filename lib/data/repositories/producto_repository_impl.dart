import '../../domain/articulos/articulo_listado.dart';
import '../../domain/articulos/articulo_vinculado_categoria.dart';
import '../../domain/articulos/variante_listado.dart';
import '../../domain/categorias/color_categoria.dart';
import '../../domain/repositories/producto_repository.dart';
import '../local/drift/app_database.dart' as drift;

class ProductoRepositoryImpl implements ProductoRepository {
  ProductoRepositoryImpl({required drift.ProductoDao productoDao})
    : _productoDao = productoDao;

  final drift.ProductoDao _productoDao;

  @override
  Future<List<ArticuloVinculadoCategoria>> obtenerArticulosPorCategoria(
    String categoriaId,
  ) async {
    final rows = await _productoDao.obtenerProductosPorCategoria(categoriaId);
    return rows
        .map(
          (row) => ArticuloVinculadoCategoria(
            productoId: row.id,
            activo: row.active,
          ),
        )
        .toList(growable: false);
  }

  @override
  Stream<List<ArticuloListado>> watchArticulos({
    String busqueda = '',
    Set<String> categoriaIds = const <String>{},
    bool incluirSinCategoria = false,
  }) {
    return _productoDao
        .watchProductosListado(
          busqueda: busqueda,
          categoriaIds: categoriaIds,
          incluirSinCategoria: incluirSinCategoria,
        )
        .map(_toDomain);
  }

  List<ArticuloListado> _toDomain(List<drift.ProductoListadoRow> rows) {
    final grouped = <String, _ArticuloBuilder>{};
    for (final row in rows) {
      final builder = grouped.putIfAbsent(
        row.producto.id,
        () =>
            _ArticuloBuilder(producto: row.producto, categoria: row.categoria),
      );
      final variante = row.variante;
      if (variante != null) {
        builder.variantes.add(variante);
      }
    }

    return grouped.values
        .map((builder) {
          builder.variantes.sort((left, right) {
            final byOrder = left.sortOrder.compareTo(right.sortOrder);
            if (byOrder != 0) return byOrder;
            return left.id.compareTo(right.id);
          });

          final defaultVariants = builder.variantes
              .where((variant) => variant.isDefault)
              .toList(growable: false);
          if (defaultVariants.length != 1) {
            throw StateError(
              'El producto ${builder.producto.id} no tiene exactamente una '
              'variante activa predeterminada.',
            );
          }

          final defaultVariant = defaultVariants.single;
          final category = builder.categoria;
          return ArticuloListado(
            productoId: builder.producto.id,
            nombre: builder.producto.name,
            activo: builder.producto.active,
            categoriaId: builder.producto.categoryId,
            categoriaNombre: category?.name,
            categoriaColor: category == null
                ? null
                : ColorCategoria.fromKey(category.colorKey),
            variantePredeterminadaId: defaultVariant.id,
            precioPredeterminadoMenor: defaultVariant.salePriceMinor,
            variantesActivas: List.unmodifiable(
              builder.variantes.map(
                (variant) => VarianteListado(
                  varianteId: variant.id,
                  nombre: null,
                  precioVentaMenor: variant.salePriceMinor,
                  predeterminada: variant.isDefault,
                  orden: variant.sortOrder,
                ),
              ),
            ),
          );
        })
        .toList(growable: false);
  }
}

class _ArticuloBuilder {
  _ArticuloBuilder({required this.producto, required this.categoria});

  final drift.ProductRow producto;
  final drift.CategoryRow? categoria;
  final List<drift.ProductVariantRow> variantes = [];
}
