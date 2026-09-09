import 'package:drift/drift.dart';

import '../../../application/sync/projections/producto_projection_store.dart';
import '../../../domain/articulos/sale_configuration.dart';
import 'app_database.dart' as drift;
import '../../../application/sync/payloads/producto_creado_payload.dart';
import '../../../application/sync/models/sync_event.dart';

class DriftProductoProjectionStore implements ProductoProjectionStore {
  DriftProductoProjectionStore({required drift.ProductoDao productoDao})
    : _productoDao = productoDao;

  final drift.ProductoDao _productoDao;

  @override
  Future<ProductoCreadoPayload> snapshot(String productId) async {
    final product = await findProductById(productId);
    if (product == null || !product.active) {
      throw StateError('El artículo no existe.');
    }
    final variants = await findVariantsByProductId(productId);
    final values = <ProductoCreadoVariante>[];
    for (final variant in variants.where((v) => v.active)) {
      final recipe = await _productoDao.obtenerComponentesRecetaPorVariante(
        variant.id,
      );
      values.add(
        ProductoCreadoVariante.create(
          id: variant.id,
          nombre: variant.nombre,
          precioVentaMenor: variant.precioVentaMenor,
          costoEstandarMenor: variant.costoEstandarMenor,
          inventoryItemId: variant.inventoryItemId,
          esPredeterminada: variant.esPredeterminada,
          orden: variant.orden,
          componentesReceta: recipe
              .map(
                (c) => ProductoCreadoComponenteReceta.create(
                  inventoryItemId: c.inventoryItemId,
                  quantityAtomic: c.quantityAtomic,
                ),
              )
              .toList(),
        ),
      );
    }
    return ProductoCreadoPayload.create(
      nombre: product.nombre,
      categoriaId: product.categoriaId,
      saleConfiguration: product.saleConfiguration,
      variantes: values,
      dependenciasInventario: {
        for (final v in values) ...[
          if (v.inventoryItemId != null) v.inventoryItemId!,
          ...v.componentesReceta.map((c) => c.inventoryItemId),
        ],
      }.map((id) => ProductoCreadoInventarioDependencia(refId: id)).toList(),
    );
  }

  @override
  Future<void> applyUpdate(
    SyncEvent event,
    ProductoCreadoPayload state, {
    bool restore = false,
    bool deleteProduct = false,
    String? baseEventId,
  }) async {
    if (restore &&
        await _productoDao.restaurarRespaldoActualizacion(
          event.eventId,
          baseEventId!,
        )) {
      return;
    }
    final product = await findProductById(event.aggregateId);
    if (product == null) {
      if (restore) return;
      throw StateError('El artículo no existe.');
    }
    if (restore && product.lastEventId != event.eventId) return;
    if (product.saleConfiguration != state.saleConfiguration) {
      throw StateError('No se puede cambiar la forma de venta.');
    }
    final previousVariants = await findVariantsByProductId(product.id);
    final keptIds = deleteProduct
        ? <String>{}
        : state.variantes.map((v) => v.id).toSet();
    final removed = previousVariants
        .where((v) => v.active && !keptIds.contains(v.id))
        .toList();
    if (!restore &&
        removed.isNotEmpty &&
        event.deliveryStatus == 'pending' &&
        event.serverSequence == null) {
      await _productoDao.guardarRespaldoActualizacion(
        event.eventId,
        product.id,
      );
    }
    final version = restore ? event.baseVersion! : event.baseVersion! + 1;
    final lastEventId = restore ? baseEventId! : event.eventId;
    final sequence = restore
        ? product.lastServerSequence
        : event.serverSequence ?? product.lastServerSequence;
    await updateProduct(
      ProductoProjection(
        id: product.id,
        nombre: state.nombre,
        categoriaId: state.categoriaId,
        saleConfiguration: product.saleConfiguration,
        active: !deleteProduct,
        version: version,
        createdEventId: product.createdEventId,
        lastEventId: lastEventId,
        lastServerSequence: sequence,
      ),
    );
    if (restore) {
      await _productoDao.eliminarVariantesAgregadas(product.id, event.eventId);
    }
    for (final v in removed) {
      final recipe = await _productoDao.obtenerComponentesRecetaPorVariante(
        v.id,
      );
      if (v.inventoryItemId == null && recipe.isEmpty) {
        await _productoDao.eliminarVarianteSinDependencias(v.id);
      } else {
        await _productoDao.actualizarVariante(
          v.id,
          drift.ProductVariantsCompanion(
            active: const Value(false),
            isDefault: const Value(false),
            version: Value(version),
            lastEventId: Value(lastEventId),
            lastServerSequence: Value(sequence),
          ),
        );
      }
    }
    if (deleteProduct) {
      // Retener el padre mientras cualquier variante histórica lo referencie.
      if ((await findVariantsByProductId(product.id)).isEmpty) {
        await _productoDao.eliminarProductoPorId(product.id);
      }
      return;
    }
    await _productoDao.prepararActualizacionVariantes(product.id, keptIds);
    for (final v in state.variantes) {
      final existing = await findVariantById(v.id);
      if (existing == null) {
        await insertVariant(
          ProductoVarianteProjection(
            id: v.id,
            productoId: product.id,
            nombre: v.nombre,
            nameKey: v.nameKey,
            precioVentaMenor: v.precioVentaMenor,
            costoEstandarMenor: v.costoEstandarMenor,
            inventoryItemId: v.inventoryItemId,
            esPredeterminada: v.esPredeterminada,
            orden: v.orden,
            active: true,
            version: version,
            createdEventId: event.eventId,
            lastEventId: lastEventId,
            lastServerSequence: sequence,
          ),
        );
      } else {
        if (existing.productoId != product.id) {
          throw StateError('La variante pertenece a otro artículo.');
        }
        await _productoDao.actualizarVariante(
          v.id,
          drift.ProductVariantsCompanion(
            active: const Value(true),
            name: Value(v.nombre),
            nameKey: Value(v.nameKey),
            salePriceMinor: Value(v.precioVentaMenor),
            standardCostMinor: Value(v.costoEstandarMenor),
            inventoryItemId: Value(v.inventoryItemId),
            isDefault: Value(v.esPredeterminada),
            sortOrder: Value(v.orden),
            version: Value(version),
            lastEventId: Value(lastEventId),
            lastServerSequence: Value(sequence),
          ),
        );
      }
      for (final c in v.componentesReceta) {
        await insertRecipeComponent(
          ProductoRecetaComponenteProjection(
            varianteId: v.id,
            inventoryItemId: c.inventoryItemId,
            quantityAtomic: c.quantityAtomic,
          ),
        );
      }
    }
  }

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
