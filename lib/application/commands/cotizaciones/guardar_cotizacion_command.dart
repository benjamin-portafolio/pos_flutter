import 'package:uuid/uuid.dart';

/// Crear una vez por intención y conservar al reintentar, incluso tras reinicio.
class GuardarCotizacionCommand {
  GuardarCotizacionCommand({
    required String saleId,
    required String expectedDraftEventId,
    String? quotationId,
    String? eventId,
    DateTime? issuedAtLocal,
  }) : saleId = saleId.trim(),
       expectedDraftEventId = expectedDraftEventId.trim(),
       quotationId = quotationId?.trim() ?? const Uuid().v4(),
       eventId = eventId?.trim() ?? const Uuid().v4(),
       issuedAtLocal = DateTime.fromMillisecondsSinceEpoch(
         ((issuedAtLocal ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000) *
             1000,
         isUtc: true,
       );

  final String saleId, expectedDraftEventId, quotationId, eventId;
  final DateTime issuedAtLocal;
}
