import '../projections/producto_proveedores_projection_store.dart';
import '../projections/proveedor_projection_store.dart';
import '../projections/variant_inventory_memory_store.dart';
import '../payloads/producto_actualizado_payload.dart';
import '../models/sync_event.dart';
import '../payloads/producto_creado_payload.dart';
import '../projections/inventory_projection_store.dart';
import '../projections/producto_projection_store.dart';

class ProductoEventHandler {
  ProductoEventHandler(
    this._productoProjectionStore, {
    required VariantInventoryMemoryStore variantInventoryMemoryStore,
    InventoryProjectionStore? inventoryProjectionStore,
    ProveedorProjectionStore? proveedorProjectionStore,
  }) : _proveedorProjectionStore = proveedorProjectionStore,
       _memoryStore = variantInventoryMemoryStore,
       _inventoryProjectionStore = inventoryProjectionStore;

  final ProveedorProjectionStore? _proveedorProjectionStore;
  final ProductoProjectionStore _productoProjectionStore;
  final VariantInventoryMemoryStore _memoryStore;
  final InventoryProjectionStore? _inventoryProjectionStore;

  Future<void> applyProductoCreado(SyncEvent event) async {
    final payload = ProductoCreadoPayload.fromJson(event.payload);
    if (event.serverSequence case final sequence?) {
      await _memoryStore.advanceEventServerSequence(event.eventId, sequence);
    }
    final existing = await _productoProjectionStore.findProductById(
      event.aggregateId,
    );

    if (existing != null) {
      if (existing.createdEventId == event.eventId) {
        final serverSequence = event.serverSequence;
        if (serverSequence != null) {
          await _productoProjectionStore.advanceLastServerSequence(
            existing.id,
            serverSequence,
          );
        }
        return;
      }

      final removed = await _removeLocalPendingProductForRemoteEvent(
        event,
        existing,
      );
      if (!removed) {
        throw StateError(
          'No se puede aplicar producto_creado sobre un producto existente: '
          '${event.aggregateId}',
        );
      }
    }

    final pendingProductsToRemove = <String>{};
    for (final variant in payload.variantes) {
      final existingVariant = await _productoProjectionStore.findVariantById(
        variant.id,
      );
      if (existingVariant == null) continue;
      final canRemoveLocalPending =
          event.serverSequence != null &&
          existingVariant.lastServerSequence == null;
      if (!canRemoveLocalPending) {
        throw StateError('Ya existe una variante con id ${variant.id}.');
      }
      pendingProductsToRemove.add(existingVariant.productoId);
    }
    for (final productId in pendingProductsToRemove) {
      await _productoProjectionStore.deleteProductById(productId);
    }

    await _validateSuppliers(payload);
    await _validateInventory(payload);

    final version = event.baseVersion ?? 1;
    await _productoProjectionStore.insertProduct(
      ProductoProjection(
        id: event.aggregateId,
        nombre: payload.nombre,
        categoriaId: payload.categoriaId,
        saleConfiguration: payload.saleConfiguration,
        active: true,
        version: version,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence,
      ),
    );
    for (final variant in payload.variantes) {
      await _productoProjectionStore.insertVariant(
        ProductoVarianteProjection(
          id: variant.id,
          productoId: event.aggregateId,
          nombre: variant.nombre,
          nameKey: variant.nameKey,
          codigoBarras: variant.codigoBarras,
          precioVentaMenor: variant.precioVentaMenor,
          costoEstandarMenor: variant.costoEstandarMenor,
          inventoryItemId: variant.inventoryItemId,
          orden: variant.orden,
          active: true,
          version: version,
          createdEventId: event.eventId,
          lastEventId: event.eventId,
          lastServerSequence: event.serverSequence,
        ),
      );
      if (variant.proveedores case final suppliers?) {
        final store = _productoProjectionStore;
        if (store is! ProductoProveedoresProjectionStore) {
          throw StateError('No se configuró la proyección de proveedores.');
        }
        await (store as ProductoProveedoresProjectionStore)
            .replaceVariantSuppliers(variant.id, suppliers);
      }
      for (final component in variant.componentesReceta) {
        await _productoProjectionStore.insertRecipeComponent(
          ProductoRecetaComponenteProjection(
            varianteId: variant.id,
            inventoryItemId: component.inventoryItemId,
            quantityAtomic: component.quantityAtomic,
          ),
        );
      }
    }
    await _maintainMemory(event, null, payload);
  }

  Future<void> applyProductoActualizado(SyncEvent event) async {
    if (event.serverSequence case final sequence?) {
      await _memoryStore.advanceEventServerSequence(event.eventId, sequence);
    }
    final payload = ProductoActualizadoPayload.fromJson(event.payload);
    final product = await _productoProjectionStore.findProductById(
      event.aggregateId,
    );
    if (payload.deleteProduct && product == null) return;
    if (product != null && product.lastEventId == event.eventId) {
      if (event.serverSequence != null) {
        await _productoProjectionStore.advanceLastServerSequence(
          product.id,
          event.serverSequence!,
        );
      }
      return;
    }
    if (product == null || !product.active) {
      throw StateError('El artículo no existe.');
    }
    if (product.lastEventId != payload.baseEventId ||
        product.version != event.baseVersion ||
        (event.baseServerSequence != null &&
            product.lastServerSequence != event.baseServerSequence)) {
      throw StateError('El artículo cambió desde que se abrió la edición.');
    }
    final current = await _productoProjectionStore.snapshot(product.id);
    if (!ProductoActualizadoPayload.sameEditingBase(current, payload.before)) {
      throw StateError('La base del artículo no coincide.');
    }
    for (final variant
        in payload.deleteProduct
            ? <ProductoCreadoVariante>[]
            : payload.after.variantes) {
      final existingVariant = await _productoProjectionStore.findVariantById(
        variant.id,
      );
      if (existingVariant != null &&
          (!existingVariant.active ||
              existingVariant.productoId != product.id)) {
        throw StateError('La variante pertenece a otro artículo.');
      }
    }
    await _validateSuppliers(payload.before);
    if (!payload.deleteProduct) {
      await _validateSuppliers(payload.after);
      await _validateInventory(payload.after);
    }
    await _productoProjectionStore.applyUpdate(
      event,
      payload.after,
      deleteProduct: payload.deleteProduct,
    );
    if (!payload.deleteProduct) {
      await _maintainMemory(event, payload.before, payload.after);
    }
  }

  Future<void> _validateSuppliers(ProductoCreadoPayload state) async {
    for (final id in state.supplierIds) {
      if (await _proveedorProjectionStore?.findById(id) == null) {
        throw StateError('No existe el proveedor $id.');
      }
    }
  }

  Future<void> _maintainMemory(
    SyncEvent event,
    ProductoCreadoPayload? before,
    ProductoCreadoPayload after,
  ) async {
    final links = <String, String?>{
      for (final v in before?.variantes ?? <ProductoCreadoVariante>[])
        v.id: v.inventoryItemId,
    };
    for (final v in after.variantes) {
      links[v.id] = v.inventoryItemId ?? links[v.id];
    }
    for (final entry in links.entries) {
      final itemId = entry.value;
      if (itemId == null) continue;
      final memory = await _memoryStore.findByVariantId(entry.key);
      if (memory?.inventoryItemId != itemId) {
        await _memoryStore.upsert(entry.key, itemId, event);
      }
    }
  }

  Future<void> _validateInventory(ProductoCreadoPayload payload) async {
    for (final variant in payload.variantes) {
      for (final component in variant.componentesReceta) {
        final inventoryStore = _inventoryProjectionStore;
        if (inventoryStore == null) {
          throw StateError(
            'No se configuró la proyección de inventario para la receta.',
          );
        }
        final item = await inventoryStore.findItemById(
          component.inventoryItemId,
        );
        if (item == null || !item.active) {
          throw StateError(
            'No existe el recurso de inventario activo '
            '${component.inventoryItemId}.',
          );
        }
        final unit = await inventoryStore.findUnitById(item.defaultUnitId);
        if (unit == null || !unit.active) {
          throw StateError(
            'La unidad del componente de receta no existe o está inactiva.',
          );
        }
      }
      final inventoryItemId = variant.inventoryItemId;
      if (inventoryItemId == null) continue;
      final linkedVariant = await _productoProjectionStore
          .findVariantByInventoryItemId(inventoryItemId);
      if (linkedVariant != null && linkedVariant.id != variant.id) {
        throw StateError(
          'El recurso $inventoryItemId ya pertenece a otra variante.',
        );
      }
      final inventoryStore = _inventoryProjectionStore;
      if (inventoryStore == null) {
        throw StateError(
          'No se configuró la proyección de inventario para la variante.',
        );
      }
      final item = await inventoryStore.findItemById(inventoryItemId);
      if (item == null || !item.active) {
        throw StateError(
          'No existe el recurso de inventario activo $inventoryItemId.',
        );
      }
      if (item.originVariantId != null && item.originVariantId != variant.id) {
        throw StateError('El recurso fue generado para otra variante.');
      }
      final inventoryUnit = await inventoryStore.findUnitById(
        item.defaultUnitId,
      );
      if (inventoryUnit == null || !inventoryUnit.active) {
        throw StateError(
          'La unidad del recurso de inventario no existe o está inactiva.',
        );
      }
      switch (payload.saleConfiguration.mode.code) {
        case 'unit':
          if (inventoryUnit.dimension != 'count' ||
              inventoryUnit.atomicFactor != 1) {
            throw StateError(
              'La venta por unidad requiere inventario en piezas.',
            );
          }
        case 'measured':
          final saleUnit = await inventoryStore.findUnitById(
            payload.saleConfiguration.saleUnitId!,
          );
          if (saleUnit == null ||
              !saleUnit.active ||
              saleUnit.dimension != inventoryUnit.dimension) {
            throw StateError(
              'La unidad de inventario no coincide con la dimensión de venta.',
            );
          }
      }
    }
  }

  Future<bool> _removeLocalPendingProductForRemoteEvent(
    SyncEvent event,
    ProductoProjection existing,
  ) async {
    if (event.serverSequence == null || existing.lastServerSequence != null) {
      return false;
    }

    await _productoProjectionStore.deleteProductById(existing.id);
    return true;
  }
}
