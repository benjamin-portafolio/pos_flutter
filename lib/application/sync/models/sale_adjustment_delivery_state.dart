/// Lectura para consulta/conciliación: libro registrado = oficial + diferencia
/// local. Un rechazo de entrega conserva la diferencia hasta resolución explícita.
class SaleAdjustmentDeliveryState {
  const SaleAdjustmentDeliveryState({
    required this.inventory,
    required this.cash,
    required this.creditReductions,
    required this.incidentEventIds,
  });
  final Map<
    String,
    ({BigInt recorded, BigInt official, BigInt localDifference})
  >
  inventory;
  final Map<
    String,
    ({BigInt recorded, BigInt official, BigInt localDifference})
  >
  cash;
  final Map<
    String,
    ({BigInt recorded, BigInt official, BigInt localDifference})
  >
  creditReductions;
  final List<String> incidentEventIds;
}
