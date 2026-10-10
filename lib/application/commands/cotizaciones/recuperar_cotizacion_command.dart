import 'package:uuid/uuid.dart';

/// Conservar esta intención (incluida su fecha) al reintentar tras reinicio.
class RecuperarCotizacionCommand {
  RecuperarCotizacionCommand({
    required String quotationId,
    required String expectedQuotationEventId,
    String? saleId,
    String? eventId,
    DateTime? recoveredAtLocal,
  }) : quotationId = quotationId.trim(),
       expectedQuotationEventId = expectedQuotationEventId.trim(),
       saleId = saleId?.trim() ?? const Uuid().v4(),
       eventId = eventId?.trim() ?? const Uuid().v4(),
       recoveredAtLocal = DateTime.fromMillisecondsSinceEpoch(
         ((recoveredAtLocal ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000) *
             1000,
         isUtc: true,
       );

  final String quotationId, expectedQuotationEventId, saleId, eventId;
  final DateTime recoveredAtLocal;
}
