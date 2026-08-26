import '../models/sync_event.dart';
import '../payloads/producto_creado_payload.dart';
import '../projections/producto_projection_store.dart';

class ProductoEventHandler {
  ProductoEventHandler(this._productoProjectionStore);

  final ProductoProjectionStore _productoProjectionStore;

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
