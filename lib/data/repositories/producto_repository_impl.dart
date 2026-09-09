import '../../domain/articulos/articulo_listado.dart';
import '../../domain/articulos/articulo_detalle.dart';
import '../../domain/articulos/variante_detalle.dart';
import '../../domain/articulos/sale_configuration.dart';
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
  Future<ArticuloDetalle?> obtenerDetalle(String productoId) async {
    final product = await _productoDao.obtenerProductoPorId(productoId);
    if (product == null || !product.active) return null;
    final rows = await _productoDao.obtenerVariantesPorProducto(productoId);
    final variants = <VarianteDetalle>[];
    for (final row in rows.where((row) => row.active)) {
      final recipe = await _productoDao.obtenerComponentesRecetaPorVariante(
        row.id,
      );
      variants.add(
        VarianteDetalle(
          id: row.id,
          nombre: row.name,
          precioVentaMenor: row.salePriceMinor,
          costoEstandarMenor: row.standardCostMinor,
          inventoryItemId: row.inventoryItemId,
          componentesReceta: Map.unmodifiable({
            for (final component in recipe)
              component.inventoryItemId: component.quantityAtomic,
          }),
        ),
      );
    }
    return ArticuloDetalle(
      lastEventId: product.lastEventId,
      nombre: product.name,
      categoriaId: product.categoryId,
      saleConfiguration: product.saleMode == 'unit'
          ? const UnitSaleConfiguration()
          : MeasuredSaleConfiguration(
              saleUnitId: product.saleUnitId!,
              priceReferenceQuantityAtomic:
                  product.priceReferenceQuantityAtomic!,
            ),
      variantes: List.unmodifiable(variants),
    );
  }

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

          if (builder.variantes.isEmpty) {
            throw StateError(
              'El producto ${builder.producto.id} no tiene variantes activas.',
            );
          }

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
            variantesActivas: List.unmodifiable(
              builder.variantes.map(
                (variant) => VarianteListado(
                  varianteId: variant.id,
                  nombre: variant.name,
                  precioVentaMenor: variant.salePriceMinor,
                  costoEstandarMenor: variant.standardCostMinor,
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
