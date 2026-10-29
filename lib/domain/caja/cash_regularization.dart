/// Diferencia reconocida fuera de la evidencia original del corte. El esperado
/// abierto incluye solo efectos que aún no están en el libro físico local.
class CashRegularization {
  const CashRegularization({
    required this.effectId,
    required this.eventId,
    required this.deltaMinor,
    required this.isRecovery,
    required this.deliveryStatus,
    this.affectsExpected = false,
  });
  final String effectId, eventId, deliveryStatus;
  final int deltaMinor;
  final bool isRecovery, affectsExpected;
}
