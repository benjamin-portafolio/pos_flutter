import '../../domain/inventario/inventory_consumption_configuration.dart';
import 'payloads/movimiento_inventario_registrado_payload.dart';
import 'payloads/producto_agregado_borrador_payload.dart';
import 'payloads/producto_actualizado_borrador_payload.dart';
import 'payloads/producto_creado_payload.dart';
import 'payloads/producto_actualizado_payload.dart';
import 'payloads/venta_confirmada_payload.dart';
import 'projections/inventory_projection_store.dart';
import 'projections/variant_inventory_tracking_store.dart';

/// La baja conserva el historial, pero exige saldo cero y ausencia de usos actuales.
class InventoryDeletionPolicy {
  const InventoryDeletionPolicy(this.inventoryStore, this.trackingStore);
  final InventoryProjectionStore inventoryStore;
  final VariantInventoryTrackingStore trackingStore;

  Future<String?> blockingReason(String id) async {
    final balance = await inventoryStore.findBalanceByItemId(id);
    if (balance == null) return 'El recurso no tiene saldo; requiere revisión.';
    if (balance.quantityOnHandAtomic != 0 ||
        balance.quantityAvailableAtomic != 0) {
      return 'No se puede eliminar un recurso con existencias distintas de cero.';
    }
    if ((await trackingStore.directLinkedVariantIds(id)).isNotEmpty) {
      return 'El recurso está vinculado a un producto. Desvincúlalo antes de eliminarlo.';
    }
    if ((await trackingStore.recipeUsingVariantIds(id)).isNotEmpty) {
      return 'El recurso forma parte de una receta. Retíralo antes de eliminarlo.';
    }
    if ((await trackingStore.unresolvedSaleIdsReferencing(
      id,
      includeConfirmed: false,
    )).isNotEmpty) {
      return 'Hay ventas pendientes que necesitan este recurso.';
    }
    for (final event in await trackingStore.unappliedInventoryEvents()) {
      final uses = switch (event.eventType) {
        MovimientoInventarioRegistradoPayload.eventType =>
          event.aggregateId == id,
        ProductoCreadoPayload.eventType => ProductoCreadoPayload.fromJson(
          event.payload,
        ).dependenciasInventario.any((d) => d.refId == id),
        ProductoActualizadoPayload.eventType =>
          ProductoActualizadoPayload.fromJson(
            event.payload,
          ).after.dependenciasInventario.any((d) => d.refId == id),
        VentaConfirmadaPayload.eventType => VentaConfirmadaPayload.fromJson(
          event.payload,
        ).lines.any((l) => l.consumptions.any((c) => c.inventoryItemId == id)),
        ProductoAgregadoBorradorPayload.eventType => _configurationUses(
          ProductoAgregadoBorradorPayload.fromJson(
            event.payload,
          ).item.consumptionConfigurationKey,
          id,
        ),
        ProductoActualizadoBorradorPayload.eventType => _configurationUses(
          ProductoActualizadoBorradorPayload.fromJson(
            event.payload,
          ).item.consumptionConfigurationKey,
          id,
        ),
        _ => false,
      };
      if (uses) {
        return 'Hay operaciones pendientes de aplicación que necesitan este recurso.';
      }
    }
    return null;
  }

  bool _configurationUses(String? key, String id) =>
      key == null ||
      InventoryConsumptionConfiguration.fromKey(
        key,
      ).inventoryItemIds.contains(id);
}
