import '../../sync/payloads/operacion_venta_conciliada_payload.dart';

/// Explicit declaration of preserved effects and any later physical recovery.
class ConciliarOperacionVentaCommand {
  const ConciliarOperacionVentaCommand({
    required this.payload,
    required this.userId,
    required this.deviceId,
  });
  final OperacionVentaConciliadaPayload payload;
  final String userId, deviceId;
}
