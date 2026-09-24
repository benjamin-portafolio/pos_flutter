class ConfirmarVentaCommand {
  const ConfirmarVentaCommand({
    required this.saleId,
    required this.expectedDraftEventId,
    required this.expectedTotalMinor,
    this.receivedMinor,
    this.clienteId,
    this.paymentMethod = 'cash',
    this.paymentReference,
  });
  final String saleId, expectedDraftEventId, paymentMethod;
  final String? clienteId, paymentReference;
  final int expectedTotalMinor;

  /// null equivale al importe exacto; nunca incluye cambio en el pago aplicado.
  final int? receivedMinor;
}
