class ConfirmarVentaCommand {
  const ConfirmarVentaCommand({
    required this.saleId,
    required this.expectedDraftEventId,
    required this.expectedTotalMinor,
    this.receivedMinor,
  });
  final String saleId, expectedDraftEventId;
  final int expectedTotalMinor;

  /// null equivale al importe exacto; nunca incluye cambio en el pago aplicado.
  final int? receivedMinor;
}
