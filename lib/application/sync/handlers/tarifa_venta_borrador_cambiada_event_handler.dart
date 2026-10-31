import 'dart:convert';
import '../../../domain/ventas/sale_status.dart';
import '../applied_local_event_reader.dart';
import '../models/sync_event.dart';
import '../payloads/inventory_movement_payload.dart';
import '../payloads/tarifa_venta_borrador_cambiada_payload.dart';
import '../projections/sale_draft_projection_store.dart';
import '../projections/sale_item_projection.dart';
import '../projections/sale_projection.dart';

class TarifaVentaBorradorCambiadaEventHandler {
  TarifaVentaBorradorCambiadaEventHandler(this.store);
  final SaleDraftProjectionStore store;
  Future<void> apply(SyncEvent event) => store.atomic(() async {
    InventoryMovementPayload.requiredUuidV4(event.eventId, 'event_id');
    InventoryMovementPayload.requiredUuidV4(event.aggregateId, 'sale_id');
    final p = TarifaVentaBorradorCambiadaPayload.fromJson(event.payload);
    if (event.aggregateType !=
            TarifaVentaBorradorCambiadaPayload.aggregateType ||
        event.eventType != TarifaVentaBorradorCambiadaPayload.eventType ||
        event.deliveryStatus != 'not_required' ||
        event.serverSequence != null ||
        event.baseVersion == null ||
        event.baseVersion! < 0 ||
        event.baseVersion! >= 9007199254740991 ||
        event.baseServerSequence != null ||
        event.createdAtServer != null ||
        event.userId.trim().isEmpty ||
        event.deviceId.trim().isEmpty) {
      throw StateError(
        'Cambio de tarifa exclusivamente local con base exacta.',
      );
    }
    final applied = await (store as AppliedLocalEventReader).appliedLocalEvent(
      event.eventId,
    );
    if (applied != null) {
      if (applied.aggregateId != event.aggregateId ||
          applied.eventType != event.eventType ||
          applied.userId != event.userId ||
          applied.deviceId != event.deviceId ||
          applied.baseVersion != event.baseVersion ||
          jsonEncode(applied.payload) != jsonEncode(p.toJson())) {
        throw StateError('Identidad de operación reutilizada.');
      }
      return;
    }
    final s = await store.findById(event.aggregateId);
    if (await store.wasCleared(event.aggregateId) ||
        (s?.version ?? 0) != event.baseVersion ||
        s?.lastEventId != p.expectedDraftEventId ||
        (s?.totalMinor ?? 0) != p.previousTotalMinor ||
        (s?.pricingMode ?? 'normal') != p.previousMode ||
        (s != null &&
            (!s.active ||
                s.status != SaleStatus.borrador ||
                s.userId != event.userId ||
                s.deviceId != event.deviceId))) {
      throw StateError('El borrador cambió o ya fue cobrado.');
    }
    final lines = (await store.items(
      event.aggregateId,
    )).where((l) => l.active).toList();
    if (lines.length != p.lines.length) {
      throw StateError('Cambió el conjunto de líneas.');
    }
    for (var i = 0; i < lines.length; i++) {
      final old = lines[i], l = p.lines[i];
      if (old.id != l.id ||
          old.saleId != event.aggregateId ||
          old.sortOrder != l.sortOrder ||
          jsonEncode(old.snapshot.toJson()) != jsonEncode(l.before.toJson()) ||
          (old.persistedTotalMinor != null &&
              old.persistedTotalMinor != l.before.totalMinor)) {
        throw StateError('Cambió una línea de la vista previa.');
      }
    }
    for (var i = 0; i < lines.length; i++) {
      final old = lines[i];
      await store.saveItem(
        SaleItemProjection(
          id: old.id,
          active: true,
          version: old.version + 1,
          createdEventId: old.createdEventId,
          lastEventId: event.eventId,
          lastServerSequence: null,
          saleId: event.aggregateId,
          sortOrder: old.sortOrder,
          snapshot: p.lines[i].after,
        ),
      );
    }
    await store.saveSale(
      SaleProjection(
        id: event.aggregateId,
        active: true,
        version: event.baseVersion! + 1,
        createdEventId: s?.createdEventId ?? event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: null,
        userId: event.userId,
        deviceId: event.deviceId,
        status: SaleStatus.borrador,
        totalMinor: p.totalMinor,
        pricingContractVersion: 2,
        pricingMode: p.pricingMode,
        createdAtLocal: s?.createdAtLocal ?? event.createdAtLocal,
        updatedAtLocal: event.createdAtLocal,
      ),
    );
  });
}
