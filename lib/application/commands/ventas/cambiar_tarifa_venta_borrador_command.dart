/// Intención durable. La vista previa conserva exactamente esta base al confirmar.
class CambiarTarifaVentaBorradorCommand {
  const CambiarTarifaVentaBorradorCommand({
    required this.operationId,
    required this.saleId,
    required this.pricingMode,
    required this.expectedVersion,
    required this.expectedDraftEventId,
    required this.expectedTotalMinor,
  });
  final String operationId, saleId, pricingMode;
  final int expectedVersion, expectedTotalMinor;
  final String? expectedDraftEventId;
}
