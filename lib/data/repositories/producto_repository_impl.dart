import '../../domain/articulos/proveedor_variante.dart';
import '../local/drift/drift_producto_projection_store.dart';
import '../../domain/articulos/articulo_listado.dart';
import '../../domain/articulos/articulo_detalle.dart';
import '../../domain/articulos/codigo_barras.dart';
import '../../domain/articulos/variante_por_codigo_barras.dart';
import '../../domain/articulos/variante_detalle.dart';
import '../../domain/articulos/sale_configuration.dart';
import '../../domain/articulos/articulo_vinculado_categoria.dart';
import '../../domain/articulos/variante_listado.dart';
import '../../domain/categorias/color_categoria.dart';
import '../../domain/inventario/dimension_unidad.dart';
import '../../domain/inventario/recurso_inventario_listado.dart';
import '../../domain/inventario/unidad_inventario.dart';
import '../../domain/repositories/producto_repository.dart';
import '../local/drift/app_database.dart' as drift;

class ProductoRepositoryImpl implements ProductoRepository {
  ProductoRepositoryImpl({required drift.ProductoDao productoDao})
    : _productoDao = productoDao;

  final drift.ProductoDao _productoDao;

  @override
  Future<List<VariantePorCodigoBarras>> buscarVariantesPorCodigoBarras(
    String codigo,
  ) async {
    final normalized = CodigoBarras.fromInput(codigo).value;
    if (normalized == null) return const [];
    final rows = await _productoDao.buscarVariantesPorCodigoBarras(normalized);
    return List.unmodifiable(
      rows.map(
        (row) => VariantePorCodigoBarras(
          productoId: row.producto.id,
          varianteId: row.variante.id,
          nombreProducto: row.producto.name,
          nombreVariante: row.variante.name,
          codigoBarras: row.variante.barcode!,
          precioVentaMenor: row.variante.salePriceMinor,
          saleConfiguration: _saleConfiguration(row.producto),
          unidadVenta: row.unidadVenta == null
              ? null
              : _toUnit(row.unidadVenta!),
        ),
      ),
    );
  }

  @override
  Future<ArticuloDetalle?> obtenerDetalle(String productoId) async {
    final product = await _productoDao.obtenerProductoPorId(productoId);
    if (product == null || !product.active) return null;
    final rows = await _productoDao.obtenerVariantesPorProducto(productoId);
    final variants = <VarianteDetalle>[];
    final supplierSets = await DriftProductoProjectionStore(
      productoDao: _productoDao,
    ).supplierSets(productoId);
    for (final row in rows.where((row) => row.active)) {
      final recipe = await _productoDao.obtenerComponentesRecetaPorVariante(
        row.id,
      );
      variants.add(
        VarianteDetalle(
          id: row.id,
          proveedores: supplierSets?[row.id]
              ?.map(
                (s) => ProveedorVariante(
                  proveedorId: s.supplierId,
                  precioInformadoMenor: s.quotedPriceMinor,
                  fechaInformadaMs: s.quotedAtMs,
                ),
              )
              .toList(),
          nombre: row.name,
          precioVentaMenor: row.salePriceMinor,
          costoEstandarMenor: row.standardCostMinor,
          codigoBarras: row.barcode,
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
      saleConfiguration: _saleConfiguration(product),
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

  @override
  Stream<int> watchVariantesActivasCount() {
    return _productoDao.watchVariantesActivasCount();
  }

  List<ArticuloListado> _toDomain(List<drift.ProductoListadoRow> rows) {
    final grouped = <String, _ArticuloBuilder>{};
    for (final row in rows) {
      final builder = grouped.putIfAbsent(
        row.producto.id,
        () => _ArticuloBuilder(
          producto: row.producto,
          categoria: row.categoria,
          unidadVenta: row.unidadVenta,
          fechaCreacion: row.fechaCreacion,
        ),
      );
      final variante = row.variante;
      if (variante != null) {
        final inventory = row.inventario;
        builder.variantes.add(
          VarianteListado(
            varianteId: variante.id,
            nombre: variante.name,
            precioVentaMenor: variante.salePriceMinor,
            costoEstandarMenor: variante.standardCostMinor,
            orden: variante.sortOrder,
            inventario: inventory == null
                ? null
                : RecursoInventarioListado(
                    id: inventory.id,
                    nombre: inventory.name,
                    activo: inventory.active,
                    existenciaAtomica: row.saldo?.quantityOnHandAtomic ?? 0,
                    unidadPredeterminada: _toUnit(row.unidadInventario!),
                  ),
          ),
        );
      }
    }

    return grouped.values
        .map((builder) {
          builder.variantes.sort((left, right) {
            final byOrder = left.orden.compareTo(right.orden);
            if (byOrder != 0) return byOrder;
            return left.varianteId.compareTo(right.varianteId);
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
            variantesActivas: List.unmodifiable(builder.variantes),
            fechaCreacion: builder.fechaCreacion,
            unidadVenta: builder.unidadVenta == null
                ? null
                : _toUnit(builder.unidadVenta!),
            cantidadReferenciaPrecioAtomica:
                builder.producto.priceReferenceQuantityAtomic,
          );
        })
        .toList(growable: false);
  }

  SaleConfiguration _saleConfiguration(drift.ProductRow row) =>
      row.saleMode == 'unit'
      ? const UnitSaleConfiguration()
      : MeasuredSaleConfiguration(
          saleUnitId: row.saleUnitId!,
          priceReferenceQuantityAtomic: row.priceReferenceQuantityAtomic!,
        );

  UnidadInventario _toUnit(drift.UnitRow row) => UnidadInventario(
    id: row.unitId,
    code: row.code,
    nombre: row.name,
    simbolo: row.symbol,
    dimension: DimensionUnidad.fromCode(row.dimension),
    factorAtomico: row.atomicFactor,
    maximosDecimales: row.maxFractionDigits,
    activa: row.active,
  );
}

class _ArticuloBuilder {
  _ArticuloBuilder({
    required this.producto,
    required this.categoria,
    required this.unidadVenta,
    required this.fechaCreacion,
  });

  final drift.ProductRow producto;
  final drift.CategoryRow? categoria;
  final drift.UnitRow? unidadVenta;
  final DateTime? fechaCreacion;
  final List<VarianteListado> variantes = [];
}
