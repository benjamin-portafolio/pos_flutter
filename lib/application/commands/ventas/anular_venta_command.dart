import '../../sync/payloads/venta_anulada_payload.dart';

/// Prepared, frozen intention; recover these same IDs/content after a retry.
/// Ejecutada por SaleAdjustmentCommandService, sin exposición en pantallas.
class AnularVentaCommand {
  const AnularVentaCommand({
    required this.payload,
    required this.userId,
    required this.deviceId,
  });
  final VentaAnuladaPayload payload;
  final String userId, deviceId;
}
