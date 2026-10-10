import 'dart:convert';
import '../models/sync_event.dart';
import '../payloads/cotizacion_guardada_payload.dart';
import '../payloads/quotation_selection_snapshot.dart';
import '../projections/quotation_projection_store.dart';
import '../projections/quotation_projection.dart';
import '../projections/quotation_item_projection.dart';
import '../projections/sale_draft_projection_store.dart';
import '../quotation_draft_validator.dart';

class CotizacionGuardadaEventHandler {
  CotizacionGuardadaEventHandler({required this.store, required this.drafts});
  final QuotationProjectionStore store;
  final SaleDraftProjectionStore drafts;

  Future<void> apply(SyncEvent event) => store.atomic(() async {
    final payload = CotizacionGuardadaPayload.fromJson(event.payload);
    payload.refs(event.aggregateId);
    if (event.aggregateType != CotizacionGuardadaPayload.aggregateType ||
        event.eventType != CotizacionGuardadaPayload.eventType ||
        event.baseVersion != 0 ||
        event.serverSequence != null ||
        event.baseServerSequence != null ||
        event.createdAtServer != null ||
        event.deliveryStatus != 'not_required' ||
        event.eventId == payload.sourceDraftEventId ||
        [
          event.eventId,
          event.userId,
          event.deviceId,
        ].any((id) => id.trim().isEmpty) ||
        event.createdAtLocal.millisecondsSinceEpoch != payload.issuedAtMs) {
      throw StateError('Guardar cotización requiere un evento local válido.');
    }
    final recorded = await store.findEventById(event.eventId);
    if (recorded != null &&
        (recorded.aggregateType != event.aggregateType ||
            recorded.aggregateId != event.aggregateId ||
            recorded.eventType != event.eventType ||
            recorded.userId != event.userId ||
            recorded.deviceId != event.deviceId ||
            recorded.baseVersion != event.baseVersion ||
            recorded.createdAtLocal.millisecondsSinceEpoch !=
                payload.issuedAtMs ||
            jsonEncode(
                  CotizacionGuardadaPayload.fromJson(recorded.payload).toJson(),
                ) !=
                jsonEncode(payload.toJson()))) {
      throw StateError('La identidad del evento ya tiene otro contenido.');
    }
    final existing = await store.findById(event.aggregateId);
    if (existing != null) {
      final items = await store.items(existing.id);
      if (existing.createdEventId != event.eventId ||
          existing.userId != event.userId ||
          existing.deviceId != event.deviceId ||
          existing.sourceSaleId != payload.sourceSaleId ||
          existing.sourceDraftEventId != payload.sourceDraftEventId ||
          existing.issuedAtLocal.millisecondsSinceEpoch != payload.issuedAtMs ||
          items.length != payload.lines.length ||
          payload.lines.any(
            (line) => !items.any(
              (item) =>
                  item.id == line.id &&
                  item.sortOrder == line.sortOrder &&
                  jsonEncode(item.selection.toJson()) ==
                      jsonEncode(line.selection.toJson()),
            ),
          )) {
        throw StateError('Colisión de identidad o contenido de cotización.');
      }
      return; // No consulta el origen ni restaura un vínculo histórico.
    }
    final active = QuotationDraftValidator.validate(
      sale: await drafts.findById(payload.sourceSaleId),
      userId: event.userId,
      deviceId: event.deviceId,
      expectedDraftEventId: payload.sourceDraftEventId,
      items: await drafts.items(payload.sourceSaleId),
    );
    if (await store.findByCurrentSaleId(payload.sourceSaleId) != null ||
        active.length != payload.lines.length ||
        payload.lines.any(
          (line) => !active.any(
            (item) =>
                item.id == line.sourceSaleItemId &&
                item.sortOrder == line.sortOrder &&
                jsonEncode(
                      QuotationSelectionSnapshot.fromSale(
                        item.snapshot,
                      ).toJson(),
                    ) ==
                    jsonEncode(line.selection.toJson()),
          ),
        )) {
      throw StateError('La captura está vinculada o sus líneas cambiaron.');
    }
    await store.insertQuotation(
      QuotationProjection(
        id: event.aggregateId,
        active: true,
        version: 1,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: null,
        userId: event.userId,
        deviceId: event.deviceId,
        issuedAtLocal: DateTime.fromMillisecondsSinceEpoch(
          payload.issuedAtMs,
          isUtc: true,
        ),
        sourceSaleId: payload.sourceSaleId,
        sourceDraftEventId: payload.sourceDraftEventId,
        currentSaleId: payload.sourceSaleId,
      ),
    );
    for (final line in payload.lines) {
      await store.insertItem(
        QuotationItemProjection(
          id: line.id,
          active: true,
          version: 1,
          createdEventId: event.eventId,
          lastEventId: event.eventId,
          lastServerSequence: null,
          quotationId: event.aggregateId,
          sortOrder: line.sortOrder,
          selection: line.selection,
        ),
      );
    }
  });
}
