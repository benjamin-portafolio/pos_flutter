import '../models/sync_event.dart';
import '../payloads/producto_creado_payload.dart';
import '../projections/inventory_projection_store.dart';
import '../projections/producto_projection_store.dart';

class ProductoEventHandler {
  ProductoEventHandler(
    this._productoProjectionStore, {
    InventoryProjectionStore? inventoryProjectionStore,
  }) : _inventoryProjectionStore = inventoryProjectionStore;

  final ProductoProjectionStore _productoProjectionStore;
  final InventoryProjectionStore? _inventoryProjectionStore;

  Future<void> applyProductoCreado(SyncEvent event) async {
    final payload = ProductoCreadoPayload.fromJson(event.payload);
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

    for (final variant in payload.variantes) {
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
          precioVentaMenor: variant.precioVentaMenor,
          costoEstandarMenor: variant.costoEstandarMenor,
          inventoryItemId: variant.inventoryItemId,
          esPredeterminada: variant.esPredeterminada,
          orden: variant.orden,
          active: true,
          version: version,
          createdEventId: event.eventId,
          lastEventId: event.eventId,
          lastServerSequence: event.serverSequence,
        ),
      );
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
