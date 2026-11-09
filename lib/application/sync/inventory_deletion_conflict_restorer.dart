import 'models/sync_event.dart';
import 'payloads/recurso_inventario_eliminado_payload.dart';
import 'projections/inventory_projection_store.dart';

/// Restaura solo la baja optimista que todavía es la punta de esta proyección.
Future<void> restoreInventoryDeletion(
  InventoryProjectionStore? store,
  SyncEvent event,
) async {
  if (store == null) return;
  final payload = RecursoInventarioEliminadoPayload.fromJson(event.payload);
  final item = await store.findItemById(event.aggregateId);
  if (item == null || item.active || item.lastEventId != event.eventId) return;
  await store.applyItemUpdate(
    item: InventoryItemProjection(
      id: item.id,
      defaultUnitId: item.defaultUnitId,
      name: item.name,
      active: true,
      version: event.baseVersion!,
      createdEventId: item.createdEventId,
      lastEventId: payload.baseEventId,
      lastServerSequence: item.lastServerSequence ?? event.baseServerSequence,
      originVariantId: item.originVariantId,
    ),
    expectedBaseEventId: event.eventId,
    expectedBaseVersion: item.version,
  );
}
