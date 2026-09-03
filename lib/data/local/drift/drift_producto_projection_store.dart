import 'package:drift/drift.dart';

import '../../../application/sync/projections/producto_projection_store.dart';
import '../../../domain/articulos/sale_configuration.dart';
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
  Future<ProductoVarianteProjection?> findVariantByInventoryItemId(
    String inventoryItemId,
  ) async {
    final row = await _productoDao.obtenerVariantePorInventoryItemId(
      inventoryItemId,
    );
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
  Future<List<ProductoProjection>> findProductsByCategoryId(
    String categoryId,
  ) async {
    final rows = await _productoDao.obtenerProductosPorCategoria(categoryId);
    return rows.map(_productFromRow).toList(growable: false);
  }

  @override
  Future<void> insertProduct(ProductoProjection projection) async {
    await _productoDao.insertarProducto(
      drift.ProductsCompanion.insert(
        id: projection.id,
        name: projection.nombre,
        categoryId: Value(projection.categoriaId),
        saleMode: Value(projection.saleConfiguration.mode.code),
        saleUnitId: Value(projection.saleConfiguration.saleUnitId),
        priceReferenceQuantityAtomic: Value(
          projection.saleConfiguration.priceReferenceQuantityAtomic,
        ),
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
        name: Value(projection.nombre),
        nameKey: Value(projection.nameKey),
        salePriceMinor: projection.precioVentaMenor,
        standardCostMinor: Value(projection.costoEstandarMenor),
        inventoryItemId: Value(projection.inventoryItemId),
        isDefault: projection.esPredeterminada,
        sortOrder: projection.orden,
        active: Value(projection.active),
        version: Value(projection.version),
        createdEventId: Value(projection.createdEventId),
        lastEventId: Value(projection.lastEventId),
        lastServerSequence: Value(projection.lastServerSequence),
      ),
    );
  }

  @override
  Future<void> insertRecipeComponent(
    ProductoRecetaComponenteProjection projection,
  ) async {
    await _productoDao.insertarComponenteReceta(
      drift.RecipeComponentsCompanion.insert(
        variantId: projection.varianteId,
        inventoryItemId: projection.inventoryItemId,
        quantityAtomic: projection.quantityAtomic,
      ),
    );
  }

  @override
  Future<void> updateProduct(ProductoProjection projection) async {
    await _productoDao.actualizarProducto(
      projection.id,
      drift.ProductsCompanion(
        name: Value(projection.nombre),
        categoryId: Value(projection.categoriaId),
        saleMode: Value(projection.saleConfiguration.mode.code),
        saleUnitId: Value(projection.saleConfiguration.saleUnitId),
        priceReferenceQuantityAtomic: Value(
          projection.saleConfiguration.priceReferenceQuantityAtomic,
        ),
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
  Future<void> advanceProductLastServerSequence(
    String productId,
    int serverSequence,
  ) {
    return _productoDao.avanzarLastServerSequenceProducto(
      productId,
      serverSequence,
    );
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
      saleConfiguration: row.saleMode == 'measured'
          ? MeasuredSaleConfiguration(
              saleUnitId: row.saleUnitId!,
              priceReferenceQuantityAtomic: row.priceReferenceQuantityAtomic!,
            )
          : const UnitSaleConfiguration(),
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
      nombre: row.name,
      nameKey: row.nameKey,
      precioVentaMenor: row.salePriceMinor,
      costoEstandarMenor: row.standardCostMinor,
      inventoryItemId: row.inventoryItemId,
      esPredeterminada: row.isDefault,
      orden: row.sortOrder,
      active: row.active,
      version: row.version,
      createdEventId: row.createdEventId,
      lastEventId: row.lastEventId,
      lastServerSequence: row.lastServerSequence,
    );
  }
}
