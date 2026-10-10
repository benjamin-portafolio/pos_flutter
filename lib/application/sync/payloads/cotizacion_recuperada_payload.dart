import '../../commands/cotizaciones/quotation_recovery_identity.dart';
import '../local_event_store.dart';
import 'cotizacion_recovery_line_identity.dart';
import 'inventory_movement_payload.dart';
import 'quotation_json.dart';

/// Vínculo exclusivamente local. Las condiciones de venta viven en sale_draft.
class CotizacionRecuperadaPayload {
  CotizacionRecuperadaPayload({
    required String baseQuotationEventId,
    required String? previousSaleId,
    required String saleId,
    required this.recoveredAtMs,
    required this.draftVersion,
    required String draftCreatedEventId,
    required String draftLastEventId,
    required List<CotizacionRecoveryLineIdentity> lines,
  }) : baseQuotationEventId = baseQuotationEventId.trim(),
       previousSaleId = previousSaleId?.trim(),
       saleId = saleId.trim(),
       draftCreatedEventId = draftCreatedEventId.trim(),
       draftLastEventId = draftLastEventId.trim(),
       lines = List.unmodifiable(lines) {
    InventoryMovementPayload.requiredUuidV4(this.saleId, 'sale_id');
    QuotationJson.date(recoveredAtMs);
    if (this.baseQuotationEventId.isEmpty ||
        this.previousSaleId?.isEmpty == true ||
        this.previousSaleId == this.saleId ||
        lines.isEmpty ||
        draftVersion != lines.length ||
        this.draftCreatedEventId != lines.first.draftEventId ||
        this.draftLastEventId != lines.last.draftEventId ||
        lines.map((l) => l.quotationItemId).toSet().length != lines.length ||
        lines.map((l) => l.saleItemId).toSet().length != lines.length ||
        lines.map((l) => l.draftEventId).toSet().length != lines.length ||
        lines.any(
          (l) =>
              l.saleItemId !=
              QuotationRecoveryIdentity.saleItem(
                this.saleId,
                l.quotationItemId,
              ),
        )) {
      throw const FormatException('Vínculo de recuperación inválido.');
    }
    for (var i = 1; i < lines.length; i++) {
      if (lines[i - 1].sortOrder >= lines[i].sortOrder) {
        throw const FormatException('Orden inválido.');
      }
    }
  }
  static const aggregateType = 'quotation', eventType = 'cotizacion_recuperada';
  final String baseQuotationEventId,
      saleId,
      draftCreatedEventId,
      draftLastEventId;
  final String? previousSaleId;
  final int recoveredAtMs, draftVersion;
  final List<CotizacionRecoveryLineIdentity> lines;

  /// Comprueba también la semilla del evento que no pertenece al JSON del vínculo.
  void validateIdentity(String eventId) {
    InventoryMovementPayload.requiredUuidV4(eventId, 'event_id');
    if (eventId == baseQuotationEventId ||
        lines.any(
          (l) =>
              l.draftEventId == eventId ||
              l.draftEventId !=
                  QuotationRecoveryIdentity.draftEvent(
                    eventId,
                    saleId,
                    l.quotationItemId,
                  ),
        )) {
      throw const FormatException('Identidades de intención incompatibles.');
    }
  }

  List<LocalEventRef> refs(String quotationId) {
    if (quotationId.trim().isEmpty ||
        quotationId == saleId ||
        lines.any(
          (l) =>
              [quotationId, saleId].contains(l.saleItemId) ||
              l.quotationItemId == saleId,
        )) {
      throw const FormatException('Referencias inválidas.');
    }
    return [
      LocalEventRef.affects(refType: aggregateType, refId: quotationId),
      LocalEventRef.uses(refType: 'sale', refId: saleId),
      for (final l in lines)
        LocalEventRef.uses(refType: 'event', refId: l.draftEventId),
    ];
  }

  Map<String, Object?> toJson() => {
    'format_version': 2,
    'base_quotation_event_id': baseQuotationEventId,
    'previous_sale_id': previousSaleId,
    'sale_id': saleId,
    'recovered_at_ms': recoveredAtMs,
    'draft_version': draftVersion,
    'draft_created_event_id': draftCreatedEventId,
    'draft_last_event_id': draftLastEventId,
    'lines': lines.map((l) => l.toJson()).toList(),
  };
  factory CotizacionRecuperadaPayload.fromJson(Map<String, Object?> j) {
    QuotationJson.keys(j, {
      'format_version',
      'base_quotation_event_id',
      'previous_sale_id',
      'sale_id',
      'recovered_at_ms',
      'draft_version',
      'draft_created_event_id',
      'draft_last_event_id',
      'lines',
    });
    if (j['format_version'] is! int || j['format_version'] != 2) {
      throw const FormatException('Formato incompatible.');
    }
    return CotizacionRecuperadaPayload(
      baseQuotationEventId: QuotationJson.text(j, 'base_quotation_event_id')!,
      previousSaleId: QuotationJson.text(j, 'previous_sale_id', nullable: true),
      saleId: QuotationJson.text(j, 'sale_id')!,
      recoveredAtMs: QuotationJson.number(j, 'recovered_at_ms')!,
      draftVersion: QuotationJson.number(j, 'draft_version')!,
      draftCreatedEventId: QuotationJson.text(j, 'draft_created_event_id')!,
      draftLastEventId: QuotationJson.text(j, 'draft_last_event_id')!,
      lines: QuotationJson.lines(
        j['lines'],
      ).map(CotizacionRecoveryLineIdentity.fromJson).toList(),
    );
  }
}
