import '../../../domain/ventas/sale_status.dart';
import '../models/sync_event.dart';
import '../payloads/producto_eliminado_borrador_payload.dart';
import '../payloads/sale_item_snapshot.dart';
import '../projections/sale_draft_projection_store.dart';
import '../projections/sale_item_projection.dart';
import '../projections/sale_projection.dart';

class VentaBorradorEliminadoEventHandler {
  VentaBorradorEliminadoEventHandler(this.store);
  final SaleDraftProjectionStore store;

  Future<void> apply(SyncEvent event) => store.atomic(() async {
    final payload = ProductoEliminadoBorradorPayload.fromJson(event.payload);
    if (event.aggregateType != ProductoEliminadoBorradorPayload.aggregateType ||
        event.serverSequence != null ||
        event.deliveryStatus != 'not_required') {
      throw StateError('La eliminación del borrador es exclusivamente local.');
    }
    if (await store.wasCleared(event.aggregateId)) return;
    final sale = await store.findById(event.aggregateId);
    final nextVersion = (event.baseVersion ?? -1) + 1;
    if (nextVersion < 1) throw StateError('El evento requiere versión base.');
    if (sale != null && sale.version >= nextVersion) return;
    if ((sale?.version ?? 0) != event.baseVersion ||
        (sale != null &&
            (!sale.active ||
                sale.status != SaleStatus.borrador ||
                sale.userId != event.userId ||
                sale.deviceId != event.deviceId))) {
      throw StateError('El borrador cambió o ya no admite eliminación.');
    }
    final lines = await store.items(event.aggregateId);
    SaleItemProjection? target;
    for (final line in lines) {
      if (line.id == payload.saleItemId && line.active) {
        target = line;
        break;
      }
    }
    if (target == null) return; // Reaplicación u operación ya efectuada.
    var total = BigInt.zero;
    for (final line in lines) {
      if (line.active && line.id != target.id) {
        total += BigInt.from(line.snapshot.totalMinor);
      }
    }
    if (total > BigInt.from(SaleItemSnapshot.maxInteger)) {
      throw const FormatException(
        'El total de la venta excede el límite permitido.',
      );
    }
    await store.deleteItem(event.aggregateId, target.id);
    await store.saveSale(
      SaleProjection(
        id: event.aggregateId,
        active: true,
        version: nextVersion,
        createdEventId: sale?.createdEventId ?? event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: null,
        userId: event.userId,
        deviceId: event.deviceId,
        status: SaleStatus.borrador,
        totalMinor: total.toInt(),
        createdAtLocal: sale?.createdAtLocal ?? event.createdAtLocal,
        updatedAtLocal: event.createdAtLocal,
      ),
    );
  });
}