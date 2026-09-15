import '../../../domain/ventas/sale_status.dart';
import '../models/sync_event.dart';
import '../payloads/producto_agregado_borrador_payload.dart';
import '../payloads/sale_item_snapshot.dart';
import '../projections/sale_draft_projection_store.dart';
import '../projections/sale_item_projection.dart';
import '../projections/sale_projection.dart';

class VentaBorradorEventHandler {
  VentaBorradorEventHandler(this.store);
  final SaleDraftProjectionStore store;

  Future<void> apply(SyncEvent event) => store.atomic(() async {
    final payload = ProductoAgregadoBorradorPayload.fromJson(event.payload);
    if (event.aggregateType != ProductoAgregadoBorradorPayload.aggregateType ||
        event.serverSequence != null ||
        event.deliveryStatus != 'not_required') {
      throw StateError('La captura del borrador es exclusivamente local.');
    }
    if (await store.wasCleared(event.aggregateId)) return;
    final sale = await store.findById(event.aggregateId);
    final nextVersion = (event.baseVersion ?? -1) + 1;
    if (nextVersion < 1) throw StateError('El evento requiere versión base.');
    // Los eventos locales se aplican en orden y llevan la cantidad absoluta.
    if (sale != null && sale.version >= nextVersion) return;
    if ((sale?.version ?? 0) != event.baseVersion ||
        (sale != null &&
            (!sale.active ||
                sale.status != SaleStatus.borrador ||
                sale.userId != event.userId ||
                sale.deviceId != event.deviceId))) {
      throw StateError('El borrador cambió o ya no admite artículos.');
    }
    final lines = await store.items(event.aggregateId);
    SaleItemProjection? previous;
    var total = BigInt.from(payload.item.totalMinor);
    for (final line in lines) {
      if (line.id == payload.saleItemId) {
        previous = line;
      } else if (line.active) {
        total += BigInt.from(line.snapshot.totalMinor);
      }
    }
    if (total > BigInt.from(SaleItemSnapshot.maxInteger)) {
      throw const FormatException(
        'El total de la venta excede el límite permitido.',
      );
    }
    if (previous != null &&
        (!previous.active ||
            !previous.snapshot.sameConditions(payload.item) ||
            previous.sortOrder != payload.sortOrder)) {
      throw StateError('La línea no admite esta actualización.');
    }
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
    await store.saveItem(
      SaleItemProjection(
        id: payload.saleItemId,
        active: true,
        version: (previous?.version ?? 0) + 1,
        createdEventId: previous?.createdEventId ?? event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: null,
        saleId: event.aggregateId,
        sortOrder: payload.sortOrder,
        snapshot: payload.item,
      ),
    );
  });
}
