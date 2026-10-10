import 'dart:convert';
import '../../../domain/ventas/sale_status.dart';
import '../models/sync_event.dart';
import '../payloads/cotizacion_recuperada_payload.dart';
import '../payloads/producto_agregado_borrador_payload.dart';
import '../payloads/sale_item_snapshot.dart';
import '../projections/quotation_projection_store.dart';
import '../projections/sale_draft_projection_store.dart';

/// Verifica el borrador creado por eventos sale_draft y avanza sólo el vínculo.
class CotizacionRecuperadaEventHandler {
  CotizacionRecuperadaEventHandler({required this.store, required this.drafts});
  final QuotationProjectionStore store;
  final SaleDraftProjectionStore drafts;
  Future<void> apply(SyncEvent event) => store.atomic(() async {
    final p = CotizacionRecuperadaPayload.fromJson(event.payload);
    p.validateIdentity(event.eventId);
    p.refs(event.aggregateId);
    final base = event.baseVersion;
    if (event.aggregateType != CotizacionRecuperadaPayload.aggregateType ||
        event.eventType != CotizacionRecuperadaPayload.eventType ||
        base == null ||
        base < 1 ||
        base >= SaleItemSnapshot.maxInteger ||
        event.serverSequence != null ||
        event.baseServerSequence != null ||
        event.createdAtServer != null ||
        event.deliveryStatus != 'not_required' ||
        event.createdAtLocal.millisecondsSinceEpoch != p.recoveredAtMs ||
        [
          event.eventId,
          event.userId,
          event.deviceId,
        ].any((id) => id.trim().isEmpty)) {
      throw StateError('Recuperar requiere un evento local válido.');
    }
    final recorded = await store.findEventById(event.eventId);
    if (recorded != null &&
        (recorded.aggregateType != event.aggregateType ||
            recorded.aggregateId != event.aggregateId ||
            recorded.eventType != event.eventType ||
            recorded.userId != event.userId ||
            recorded.deviceId != event.deviceId ||
            recorded.baseVersion != base ||
            recorded.createdAtLocal.millisecondsSinceEpoch != p.recoveredAtMs ||
            jsonEncode(
                  CotizacionRecuperadaPayload.fromJson(
                    recorded.payload,
                  ).toJson(),
                ) !=
                jsonEncode(p.toJson()))) {
      throw StateError('La identidad del evento ya tiene otro contenido.');
    }
    final q = await store.findById(event.aggregateId);
    if (q == null ||
        !q.active ||
        q.userId != event.userId ||
        q.deviceId != event.deviceId) {
      throw StateError('La cotización no pertenece al contexto actual.');
    }
    if (q.version >= base + 1) {
      if ((q.version == base + 1 && q.lastEventId != event.eventId) ||
          (q.lastEventId != event.eventId &&
              recorded?.applicationStatus != 'applied')) {
        throw StateError('Otra recuperación ocupa esta revisión.');
      }
      return; // No impone otra vez cantidades ni restaura vínculos históricos.
    }
    if (await drafts.wasCleared(p.saleId)) return;
    if (q.version != base ||
        q.lastEventId != p.baseQuotationEventId ||
        q.currentSaleId != p.previousSaleId ||
        p.saleId == q.sourceSaleId) {
      throw StateError('La cotización cambió antes de recuperar.');
    }
    final linked = q.currentSaleId == null
        ? null
        : await drafts.findById(q.currentSaleId!);
    if (linked != null &&
        (linked.userId != event.userId ||
            linked.deviceId != event.deviceId ||
            linked.status == SaleStatus.confirmada ||
            (linked.active && linked.status == SaleStatus.borrador))) {
      throw StateError('La cotización ya está vendida o en captura.');
    }
    final sale = await drafts.findById(p.saleId);
    final current = await drafts.findDraft(event.userId, event.deviceId);
    if (sale == null ||
        current?.id != sale.id ||
        !sale.active ||
        sale.status != SaleStatus.borrador ||
        sale.userId != event.userId ||
        sale.deviceId != event.deviceId ||
        sale.version != p.draftVersion ||
        sale.createdEventId != p.draftCreatedEventId ||
        sale.lastEventId != p.draftLastEventId ||
        sale.createdAtLocal.millisecondsSinceEpoch != p.recoveredAtMs ||
        sale.updatedAtLocal.millisecondsSinceEpoch != p.recoveredAtMs) {
      throw StateError('El borrador no acredita el vínculo de recuperación.');
    }
    final selection = await store.items(q.id);
    final lines = await drafts.items(sale.id);
    if (selection.length != p.lines.length || lines.length != p.lines.length) {
      throw StateError('Las líneas no acreditan la recuperación.');
    }
    var total = BigInt.zero;
    for (var i = 0; i < p.lines.length; i++) {
      final identity = p.lines[i];
      final item = selection
          .where((s) => s.id == identity.quotationItemId)
          .firstOrNull;
      final line = lines.where((l) => l.id == identity.saleItemId).firstOrNull;
      final draftEvent = await store.findEventById(identity.draftEventId);
      if (item == null ||
          !item.active ||
          item.sortOrder != identity.sortOrder ||
          line == null ||
          !line.active ||
          line.version != 1 ||
          line.saleId != sale.id ||
          line.sortOrder != identity.sortOrder ||
          line.createdEventId != identity.draftEventId ||
          line.lastEventId != identity.draftEventId ||
          draftEvent == null ||
          draftEvent.aggregateType !=
              ProductoAgregadoBorradorPayload.aggregateType ||
          draftEvent.eventType != ProductoAgregadoBorradorPayload.eventType ||
          draftEvent.aggregateId != sale.id ||
          draftEvent.baseVersion != i ||
          draftEvent.userId != event.userId ||
          draftEvent.deviceId != event.deviceId ||
          draftEvent.applicationStatus != 'applied' ||
          draftEvent.deliveryStatus != 'not_required' ||
          draftEvent.serverSequence != null ||
          draftEvent.baseServerSequence != null ||
          draftEvent.createdAtServer != null ||
          draftEvent.createdAtLocal.millisecondsSinceEpoch != p.recoveredAtMs) {
        throw StateError('Identidades de borrador incompatibles.');
      }
      final captured = ProductoAgregadoBorradorPayload.fromJson(
        draftEvent.payload,
      );
      final s = item.selection, actual = line.snapshot;
      if (captured.saleItemId != line.id ||
          captured.sortOrder != line.sortOrder ||
          jsonEncode(captured.item.toJson()) != jsonEncode(actual.toJson()) ||
          s.variantId != actual.variantId ||
          s.saleMode != actual.saleMode ||
          s.quantity != actual.quantity ||
          s.measuredQuantityAtomic != actual.measuredQuantityAtomic ||
          s.unitCode != actual.unitCode ||
          s.unitSymbol != actual.unitSymbol ||
          s.unitAtomicFactor != actual.unitAtomicFactor ||
          (line.persistedTotalMinor != null &&
              line.persistedTotalMinor != actual.totalMinor)) {
        throw StateError('La selección y el borrador difieren.');
      }
      total += BigInt.from(actual.totalMinor);
    }
    if (total > BigInt.from(SaleItemSnapshot.maxInteger) ||
        total != BigInt.from(sale.totalMinor)) {
      throw StateError('El total del borrador es inválido.');
    }
    await store.linkRecoveredSale(
      quotationId: q.id,
      baseVersion: base,
      baseEventId: p.baseQuotationEventId,
      previousSaleId: p.previousSaleId,
      saleId: p.saleId,
      eventId: event.eventId,
    );
  });
}
