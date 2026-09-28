/// Saldo inicial declarado de la cuenta bancaria, para consulta.
///
/// No es una caja ni una sesión: no tiene `status` ni ciclo de vida. Solo el
/// `deliveryStatus` resuelve por join a `events`, igual que `CashSession` lo
/// hace para caja, para que la UI pueda mostrar el chip de estado.
class AccountBalanceBaseline {
  AccountBalanceBaseline({
    required this.id,
    required this.deviceId,
    required this.declaredByUserId,
    required this.amountMinor,
    required this.asOfMs,
    required this.createdEventId,
    required this.lastEventId,
    required this.deliveryStatus,
    this.rejectionReason,
  });

  final String id,
      deviceId,
      declaredByUserId,
      createdEventId,
      lastEventId,
      deliveryStatus;
  final int amountMinor;
  final int asOfMs;
  final String? rejectionReason;

  /// El saldo llegó al servidor, o la instalación es local y no requiere envío.
  bool get isDelivered =>
      deliveryStatus == 'delivered' || deliveryStatus == 'not_required';

  /// El servidor no lo aceptó y el importe declarado puede no ser el bueno.
  bool get needsAttention =>
      deliveryStatus == 'conflict' || deliveryStatus == 'rejected';
}
