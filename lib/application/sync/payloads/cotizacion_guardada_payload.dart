import '../local_event_store.dart';
import 'cotizacion_guardada_line.dart';
import 'quotation_json.dart';

/// Contrato local nuevo; no acepta formatos legados ni se envía al servidor.
class CotizacionGuardadaPayload {
  CotizacionGuardadaPayload({
    required String sourceSaleId,
    required String sourceDraftEventId,
    required this.issuedAtMs,
    required List<CotizacionGuardadaLine> lines,
  }) : sourceSaleId = sourceSaleId.trim(),
       sourceDraftEventId = sourceDraftEventId.trim(),
       lines = List.unmodifiable(lines) {
    final sourceIds = lines.map((line) => line.sourceSaleItemId).toSet();
    if (this.sourceSaleId.isEmpty ||
        this.sourceDraftEventId.isEmpty ||
        issuedAtMs <= 0 ||
        issuedAtMs > QuotationJson.maxInteger ||
        issuedAtMs % 1000 != 0 ||
        lines.isEmpty ||
        lines.map((line) => line.id).toSet().length != lines.length ||
        sourceIds.length != lines.length ||
        lines.map((line) => line.sortOrder).toSet().length != lines.length ||
        lines.any(
          (line) => sourceIds.contains(line.id) || line.id == this.sourceSaleId,
        )) {
      throw const FormatException('Cotización o líneas inválidas.');
    }
    for (var i = 1; i < lines.length; i++) {
      if (lines[i - 1].sortOrder >= lines[i].sortOrder) {
        throw const FormatException('Orden inválido.');
      }
    }
  }

  static const aggregateType = 'quotation';
  static const eventType = 'cotizacion_guardada';
  final String sourceSaleId, sourceDraftEventId;
  final int issuedAtMs;
  final List<CotizacionGuardadaLine> lines;

  List<LocalEventRef> refs(String quotationId) {
    final refs = [
      LocalEventRef.affects(refType: aggregateType, refId: quotationId),
      for (final line in lines)
        LocalEventRef.affects(refType: 'quotation_item', refId: line.id),
      LocalEventRef.uses(refType: 'sale', refId: sourceSaleId),
    ];
    if (quotationId.trim().isEmpty ||
        quotationId == sourceSaleId ||
        lines.any(
          (line) =>
              line.id == quotationId ||
              line.id !=
                  CotizacionGuardadaLine.idFor(
                    quotationId,
                    line.sourceSaleItemId,
                  ),
        ) ||
        refs.any(
          (ref) => ref.refType.trim().isEmpty || ref.refId.trim().isEmpty,
        )) {
      throw const FormatException('Referencias de cotización inválidas.');
    }
    return refs;
  }

  Map<String, Object?> toJson() => {
    'format_version': 2,
    'source_sale_id': sourceSaleId,
    'source_draft_event_id': sourceDraftEventId,
    'issued_at_ms': issuedAtMs,
    'lines': lines.map((line) => line.toJson()).toList(),
  };

  factory CotizacionGuardadaPayload.fromJson(Map<String, Object?> json) {
    QuotationJson.keys(json, {
      'format_version',
      'source_sale_id',
      'source_draft_event_id',
      'issued_at_ms',
      'lines',
    });
    if (json['format_version'] is! int || json['format_version'] != 2) {
      throw const FormatException('Formato incompatible.');
    }
    final lines = json['lines'];
    if (json['source_sale_id'] is! String ||
        json['source_draft_event_id'] is! String ||
        json['issued_at_ms'] is! int ||
        lines is! List ||
        lines.any((line) => line is! Map<String, Object?>)) {
      throw const FormatException('Payload de cotización inválido.');
    }
    return CotizacionGuardadaPayload(
      sourceSaleId: json['source_sale_id']! as String,
      sourceDraftEventId: json['source_draft_event_id']! as String,
      issuedAtMs: json['issued_at_ms']! as int,
      lines: lines
          .map(
            (line) =>
                CotizacionGuardadaLine.fromJson(line as Map<String, Object?>),
          )
          .toList(),
    );
  }
}
