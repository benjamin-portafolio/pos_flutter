import '../../../domain/ventas/sale_status.dart';
import '../models/sync_event.dart';
import '../payloads/venta_borrador_limpiada_payload.dart';
import '../projections/sale_draft_projection_store.dart';

class VentaBorradorLimpiadaEventHandler {
  VentaBorradorLimpiadaEventHandler(this.store);
  final SaleDraftProjectionStore store;

  Future<void> apply(SyncEvent event) => store.atomic(() async {
    final payload = VentaBorradorLimpiadaPayload.fromJson(event.payload);
    if (event.aggregateType != VentaBorradorLimpiadaPayload.aggregateType ||
        event.eventType != VentaBorradorLimpiadaPayload.eventType ||
        event.serverSequence != null ||
        event.deliveryStatus != 'not_required' ||
        event.baseVersion == null ||
        event.baseVersion! < 1) {
      throw StateError(
        'La limpieza del borrador requiere un evento local válido.',
      );
    }
    final sale = await store.findById(event.aggregateId);
    if (sale == null) return;
    if (!sale.active ||
        sale.status != SaleStatus.borrador ||
        sale.userId != event.userId ||
        sale.deviceId != event.deviceId ||
        sale.version != event.baseVersion) {
      throw StateError('El borrador cambió o ya no admite limpieza.');
    }
    final items = await store.items(sale.id);
    if (items.length != payload.saleItemIds.length ||
        !payload.saleItemIds.toSet().containsAll(
          items.map((item) => item.id),
        )) {
      throw StateError('Las líneas del borrador cambiaron.');
    }
    await store.deleteDraft(sale.id);
  });
}
