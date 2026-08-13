import 'package:drift/drift.dart';

import '../../../application/sync/projections/producto_projection_store.dart';
import 'app_database.dart' as drift;

class DriftProductoProjectionStore implements ProductoProjectionStore {
  DriftProductoProjectionStore({required drift.ProductoDao productoDao})
    : _productoDao = productoDao;

  final drift.ProductoDao _productoDao;

  @override
  Future<ProductoProjection?> findProductById(String id) async {
    final row = await _productoDao.obtenerProductoPorId(id);
    return row == null ? null : _productFromRow(row);
  }

  @override
  Future<ProductoVarianteProjection?> findVariantById(String id) async {
    final row = await _productoDao.obtenerVariantePorId(id);
    return row == null ? null : _variantFromRow(row);
  }

  @override
  Future<List<ProductoVarianteProjection>> findVariantsByProductId(
    String productId,
  ) async {
    final rows = await _productoDao.obtenerVariantesPorProducto(productId);
    return rows.map(_variantFromRow).toList(growable: false);
  }

  @override
  Future<int> countProductsByCategoryId(String categoryId) {
    return _productoDao.contarProductosPorCategoria(categoryId);
  }

  @override
  Future<void> insertProduct(ProductoProjection projection) async {
    await _productoDao.insertarProducto(
      drift.ProductsCompanion.insert(
        id: projection.id,
        name: projection.nombre,
        categoryId: Value(projection.categoriaId),
        active: Value(projection.active),
        version: Value(projection.version),
        createdEventId: Value(projection.createdEventId),
        lastEventId: Value(projection.lastEventId),
        lastServerSequence: Value(projection.lastServerSequence),
      ),
    );
  }

  @override
  Future<void> insertVariant(ProductoVarianteProjection projection) async {
    await _productoDao.insertarVariante(
      drift.ProductVariantsCompanion.insert(
        id: projection.id,
        productId: projection.productoId,
        salePriceMinor: projection.precioVentaMenor,
        isDefault: projection.esPredeterminada,
        sortOrder: projection.orden,
        inventoryBehavior: Value(projection.comportamientoInventario),
        active: Value(projection.active),
        version: Value(projection.version),
        createdEventId: Value(projection.createdEventId),
        lastEventId: Value(projection.lastEventId),
        lastServerSequence: Value(projection.lastServerSequence),
      ),
    );
  }

  @override
  Future<void> advanceLastServerSequence(String productId, int serverSequence) {
    return _productoDao.avanzarLastServerSequence(productId, serverSequence);
  }

  @override
  Future<void> deleteProductById(String id) {
    return _productoDao.eliminarProductoPorId(id);
  }

  @override
  Future<void> deleteCreatedByEvent(String eventId) {
    return _productoDao.eliminarProductoCreadoPorEvento(eventId);
  }

  ProductoProjection _productFromRow(drift.ProductRow row) {
    return ProductoProjection(
      id: row.id,
      nombre: row.name,
      categoriaId: row.categoryId,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }

  ProductoVarianteProjection _variantFromRow(drift.ProductVariantRow row) {
    return ProductoVarianteProjection(
      id: row.id,
      productoId: row.productId,
      precioVentaMenor: row.salePriceMinor,
      esPredeterminada: row.isDefault,
      orden: row.sortOrder,
      comportamientoInventario: row.inventoryBehavior,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }
}
