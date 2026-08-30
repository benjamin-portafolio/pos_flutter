import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/categoria_eliminada_payload.dart';
import 'payloads/categoria_movida_payload.dart';
import 'payloads/producto_creado_payload.dart';
import 'payloads/recurso_inventario_creado_payload.dart';
import 'payloads/recurso_inventario_actualizado_payload.dart';
import 'payloads/movimiento_inventario_registrado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/inventory_projection_store.dart';
import 'projections/producto_projection_store.dart';

class ServerEchoAcknowledger {
  ServerEchoAcknowledger({
    required CategoriaProjectionStore categoriaProjectionStore,
    ProductoProjectionStore? productoProjectionStore,
    InventoryProjectionStore? inventoryProjectionStore,
  }) : _categoriaProjectionStore = categoriaProjectionStore,
       _productoProjectionStore = productoProjectionStore,
       _inventoryProjectionStore = inventoryProjectionStore;

  final CategoriaProjectionStore _categoriaProjectionStore;
  final ProductoProjectionStore? _productoProjectionStore;
  final InventoryProjectionStore? _inventoryProjectionStore;

  Future<void> acknowledge(SyncEvent event) async {
    final serverSequence = event.serverSequence;
    if (serverSequence == null) return;

    switch (event.eventType) {
      case CategoriaCreadaPayload.eventType:
      case CategoriaActualizadaPayload.eventType:
        await _categoriaProjectionStore.advanceLastServerSequence(
          event.aggregateId,
          serverSequence,
        );
        return;
      case CategoriaMovidaPayload.eventType:
        final payload = CategoriaMovidaPayload.fromJson(event.payload);
        await _categoriaProjectionStore.advanceLastServerSequence(
          event.aggregateId,
          serverSequence,
        );
        await _categoriaProjectionStore.advanceLastServerSequence(
          payload.categoriaDesplazadaId,
          serverSequence,
        );
        return;
      case CategoriaEliminadaPayload.eventType:
        final payload = CategoriaEliminadaPayload.fromJson(event.payload);
        for (final product in payload.productosVinculados) {
          await _productoProjectionStore?.advanceProductLastServerSequence(
            product.productoId,
            serverSequence,
          );
        }
        for (final category in payload.categoriasDesplazadas) {
          await _categoriaProjectionStore.advanceLastServerSequence(
            category.categoriaId,
            serverSequence,
          );
        }
        return;
      case ProductoCreadoPayload.eventType:
        await _productoProjectionStore?.advanceLastServerSequence(
          event.aggregateId,
          serverSequence,
        );
        return;
      case RecursoInventarioCreadoPayload.eventType:
        await _inventoryProjectionStore?.advanceCreationServerSequence(
          inventoryItemId: event.aggregateId,
          eventId: event.eventId,
          serverSequence: serverSequence,
        );
        return;
      case RecursoInventarioActualizadoPayload.eventType:
        await _inventoryProjectionStore?.advanceEventServerSequence(
          inventoryItemId: event.aggregateId,
          eventId: event.eventId,
          serverSequence: serverSequence,
          includesBalance: false,
        );
        return;
      case MovimientoInventarioRegistradoPayload.eventType:
        await _inventoryProjectionStore?.advanceEventServerSequence(
          inventoryItemId: event.aggregateId,
          eventId: event.eventId,
          serverSequence: serverSequence,
          includesBalance: true,
        );
        return;
    }
  }
}
