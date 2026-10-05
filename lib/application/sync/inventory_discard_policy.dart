import 'payloads/movimiento_inventario_registrado_payload.dart';
import 'payloads/producto_agregado_borrador_payload.dart';
import 'payloads/producto_actualizado_borrador_payload.dart';
import 'payloads/venta_confirmada_payload.dart';
import 'projections/inventory_projection_store.dart';
import 'projections/variant_inventory_memory_store.dart';
import 'projections/variant_inventory_tracking_store.dart';
import '../../domain/inventario/inventory_consumption_configuration.dart';

/// Decisión conservadora, revalidada dentro de la transacción del descarte.
class InventoryDiscardPolicy {
  const InventoryDiscardPolicy({
    required this.trackingStore,
    required this.memoryStore,
  });
  final VariantInventoryTrackingStore trackingStore;
  final VariantInventoryMemoryStore memoryStore;

  /// Null autoriza el descarte; un motivo conserva el recurso. Los errores
  /// técnicos se propagan: nunca se convierten en permiso para borrar.
  Future<String?> preservationReason(
    InventoryItemProjection item,
    String variantId,
  ) async {
    if (!item.active) return 'El recurso está inactivo.';
    if (item.originVariantId != variantId) {
      return 'No hay procedencia acreditada para esta variante.';
    }
    if ((await trackingStore.directLinkedVariantIds(item.id)).isNotEmpty) {
      return 'Hay variantes que mantienen el vínculo directo.';
    }
    if ((await trackingStore.recipeUsingVariantIds(item.id)).isNotEmpty) {
      return 'El recurso forma parte de una receta.';
    }
    if (await trackingStore.movementCount(item.id) != 0) {
      return 'El recurso tiene historial de movimientos.';
    }
    final balance = await trackingStore.balanceOf(item.id);
    if (balance == null) {
      return 'Falta el balance del recurso; requiere revisión.';
    }
    if (!balance.isZero) return 'El recurso tiene existencias.';
    if ((await memoryStore.findByInventoryItemId(
      item.id,
    )).any((m) => m.variantId != variantId)) {
      return 'Otra variante recuerda este recurso.';
    }
    if ((await trackingStore.unresolvedSaleIdsReferencing(item.id)).isNotEmpty) {
      return 'Hay capturas de venta que todavía necesitan el recurso.';
    }
    for (final event in await trackingStore.unappliedInventoryEvents()) {
      switch (event.eventType) {
        case MovimientoInventarioRegistradoPayload.eventType:
          // Decode even if aggregate differs: a malformed applicable operation is
          // an inconsistency, not proof that the resource is unused.
          MovimientoInventarioRegistradoPayload.fromJson(event.payload);
          if (event.aggregateId == item.id) {
            return 'Hay un movimiento pendiente de aplicación.';
          }
        case VentaConfirmadaPayload.eventType:
          final sale = VentaConfirmadaPayload.fromJson(event.payload);
          if (sale.lines.any(
            (l) => l.consumptions.any((c) => c.inventoryItemId == item.id),
          )) {
            return 'Hay una venta pendiente de aplicación.';
          }
        case ProductoAgregadoBorradorPayload.eventType:
          final key = ProductoAgregadoBorradorPayload.fromJson(
            event.payload,
          ).item.consumptionConfigurationKey;
          if (key == null ||
              InventoryConsumptionConfiguration.fromKey(
                key,
              ).inventoryItemIds.contains(item.id)) {
            return 'Hay una captura pendiente de aplicación.';
          }
        case ProductoActualizadoBorradorPayload.eventType:
          final key = ProductoActualizadoBorradorPayload.fromJson(
            event.payload,
          ).item.consumptionConfigurationKey;
          if (key == null ||
              InventoryConsumptionConfiguration.fromKey(
                key,
              ).inventoryItemIds.contains(item.id)) {
            return 'Hay una captura pendiente de aplicación.';
          }
      }
    }
    return null;
  }
}
