import 'categoria_conflict_projection_restorer.dart';
import 'categoria_eliminada_conflict_projection_restorer.dart';
import 'categoria_movida_conflict_projection_restorer.dart';
import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/categoria_eliminada_payload.dart';
import 'payloads/categoria_movida_payload.dart';
import 'payloads/espacio_creado_payload.dart';
import 'payloads/producto_creado_payload.dart';
import 'payloads/movimiento_inventario_registrado_payload.dart';
import 'payloads/recurso_inventario_actualizado_payload.dart';
import 'payloads/recurso_inventario_creado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/espacio_projection_store.dart';
import 'projections/producto_projection_store.dart';
import 'projections/inventory_projection_store.dart';

class SyncConflictProjectionCleaner {
  SyncConflictProjectionCleaner({
    required EspacioProjectionStore espacioProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
    ProductoProjectionStore? productoProjectionStore,
    InventoryProjectionStore? inventoryProjectionStore,
    required CategoriaConflictProjectionRestorer
    categoriaConflictProjectionRestorer,
    required CategoriaMovidaConflictProjectionRestorer
    categoriaMovidaConflictProjectionRestorer,
    CategoriaEliminadaConflictProjectionRestorer?
    categoriaEliminadaConflictProjectionRestorer,
  }) : _espacioProjectionStore = espacioProjectionStore,
       _categoriaProjectionStore = categoriaProjectionStore,
       _productoProjectionStore = productoProjectionStore,
       _inventoryProjectionStore = inventoryProjectionStore,
       _categoriaConflictProjectionRestorer =
           categoriaConflictProjectionRestorer,
       _categoriaMovidaConflictProjectionRestorer =
           categoriaMovidaConflictProjectionRestorer,
       _categoriaEliminadaConflictProjectionRestorer =
           categoriaEliminadaConflictProjectionRestorer;

  final EspacioProjectionStore _espacioProjectionStore;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final ProductoProjectionStore? _productoProjectionStore;
  final InventoryProjectionStore? _inventoryProjectionStore;
  final CategoriaConflictProjectionRestorer
  _categoriaConflictProjectionRestorer;
  final CategoriaMovidaConflictProjectionRestorer
  _categoriaMovidaConflictProjectionRestorer;
  final CategoriaEliminadaConflictProjectionRestorer?
  _categoriaEliminadaConflictProjectionRestorer;

  Future<void> hideConflictProjection(SyncEvent event) async {
    if (event.eventType == EspacioCreadoPayload.eventType) {
      await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType == CategoriaCreadaPayload.eventType) {
      await _categoriaProjectionStore.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType == CategoriaActualizadaPayload.eventType) {
      await _categoriaConflictProjectionRestorer.restore(event);
    } else if (event.eventType == CategoriaMovidaPayload.eventType) {
      await _categoriaMovidaConflictProjectionRestorer.restore(event);
    } else if (event.eventType == CategoriaEliminadaPayload.eventType) {
      await _categoriaEliminadaConflictProjectionRestorer?.restore(event);
    } else if (event.eventType == ProductoCreadoPayload.eventType) {
      await _productoProjectionStore?.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType == RecursoInventarioCreadoPayload.eventType) {
      await _inventoryProjectionStore?.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType ==
        RecursoInventarioActualizadoPayload.eventType) {
      final payload = RecursoInventarioActualizadoPayload.fromJson(
        event.payload,
      );
      await _inventoryProjectionStore?.restoreItemUpdate(
        inventoryItemId: event.aggregateId,
        eventId: event.eventId,
        baseEventId: payload.baseEventId,
        baseVersion: event.baseVersion!,
        baseServerSequence: event.baseServerSequence,
        previousName: payload.previousName,
        nextName: payload.nextName,
      );
    } else if (event.eventType ==
        MovimientoInventarioRegistradoPayload.eventType) {
      final payload = MovimientoInventarioRegistradoPayload.fromJson(
        event.payload,
      );
      await _inventoryProjectionStore?.restoreMovement(
        inventoryItemId: event.aggregateId,
        eventId: event.eventId,
        baseEventId: payload.baseEventId,
        baseVersion: event.baseVersion!,
        baseServerSequence: event.baseServerSequence,
        movementId: payload.movement.movementId,
        quantityDeltaAtomic: payload.movement.quantityDeltaAtomic,
      );
    }
  }
}
