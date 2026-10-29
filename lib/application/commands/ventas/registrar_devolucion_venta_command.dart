import '../../sync/payloads/devolucion_venta_registrada_payload.dart';

/// Prepared, frozen intention; recover these same IDs/content after a retry.
/// Ejecutada por SaleAdjustmentCommandService, sin exposición en pantallas.
class RegistrarDevolucionVentaCommand {
  const RegistrarDevolucionVentaCommand({
    required this.payload,
    required this.userId,
    required this.deviceId,
  });
  final DevolucionVentaRegistradaPayload payload;
  final String userId, deviceId;
}
