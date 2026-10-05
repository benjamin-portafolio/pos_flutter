import '../inventory_discard_policy.dart';
import '../models/sync_event.dart';
import '../payloads/producto_actualizado_payload.dart';
import '../payloads/recurso_inventario_descartado_payload.dart';
import '../projections/inventory_projection_store.dart';
import '../projections/producto_projection_store.dart';
import '../projections/variant_inventory_tracking_store.dart';
import '../synced_event_history.dart';

class InventoryDiscardEventHandler {
  const InventoryDiscardEventHandler({
    required this.inventoryStore,
    required this.productStore,
    required this.trackingStore,
    required this.history,
    required this.policy,
    required this.isStandalone,
  });
  final InventoryProjectionStore inventoryStore;
  final ProductoProjectionStore productStore;
  final VariantInventoryTrackingStore trackingStore;
  final SyncedEventHistory history;
  final InventoryDiscardPolicy policy;
  final bool Function() isStandalone;

  Future<void> apply(SyncEvent event) async {
    final payload = RecursoInventarioDescartadoPayload.fromJson(event.payload);
    if (!isStandalone() ||
        event.deliveryStatus !=
            RecursoInventarioDescartadoPayload.deliveryStatus ||
        event.serverSequence != null ||
        event.aggregateType !=
            RecursoInventarioDescartadoPayload.aggregateType) {
      throw StateError('El descarte solo se aplica a eventos standalone.');
    }
    final item = await inventoryStore.findItemById(event.aggregateId);
    final discard = await trackingStore.appliedDiscard(event.aggregateId);
    if (item == null) {
      if (discard?.discardEventId == event.eventId &&
          discard?.triggerProductEventId == payload.triggerProductEventId &&
          discard?.event.payloadJson == event.payloadJson &&
          discard?.event.baseVersion == event.baseVersion &&
          discard?.event.baseServerSequence == event.baseServerSequence) {
        return;
      }
      throw StateError(
        'Falta el recurso sin prueba de este descarte aplicado.',
      );
    }
    if (discard != null) {
      throw StateError(
        'Un recurso descartado no puede reutilizar su identidad.',
      );
    }
    if (item.lastEventId != payload.baseEventId ||
        item.version != event.baseVersion ||
        item.lastServerSequence != event.baseServerSequence) {
      throw StateError('La base del recurso cambió antes del descarte.');
    }
    final trigger = await history.eventById(payload.triggerProductEventId);
    if (trigger == null ||
        trigger.aggregateType != ProductoActualizadoPayload.aggregateType ||
        trigger.aggregateId != payload.triggerProductId ||
        trigger.eventType != ProductoActualizadoPayload.eventType ||
        trigger.applicationStatus != 'applied' ||
        trigger.deliveryStatus != 'not_required') {
      throw StateError(
        'No hay un evento de producto aplicado que acredite el descarte.',
      );
    }
    final update = ProductoActualizadoPayload.fromJson(trigger.payload);
    final before = update.before.variantes
        .where((v) => v.id == payload.originVariantId)
        .firstOrNull;
    final after = update.after.variantes
        .where((v) => v.id == payload.originVariantId)
        .firstOrNull;
    final product = await productStore.findProductById(
      payload.triggerProductId,
    );
    if (update.deleteProduct ||
        before?.inventoryItemId != item.id ||
        after == null ||
        after.inventoryItemId != null ||
        product?.lastEventId != trigger.eventId) {
      throw StateError('El disparador no desvinculó esta variante conservada.');
    }
    final reason = await policy.preservationReason(
      item,
      payload.originVariantId,
    );
    if (reason != null) {
      throw StateError('El recurso no es descartable: $reason');
    }
    await trackingStore.discardResource(
      inventoryItemId: item.id,
      discardEventId: event.eventId,
      triggerProductEventId: trigger.eventId,
    );
  }
}
