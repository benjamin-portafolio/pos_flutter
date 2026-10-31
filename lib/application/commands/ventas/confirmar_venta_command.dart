class ConfirmarVentaCommand {
  const ConfirmarVentaCommand({
    required this.saleId,
    required this.expectedDraftEventId,
    required this.expectedTotalMinor,
    this.expectedVersion,
    this.receivedMinor,
    this.clienteId,
    this.paymentMethod = 'cash',
    this.paymentReference,
  });
  final String saleId, expectedDraftEventId, paymentMethod;
  final String? clienteId, paymentReference;
  final int expectedTotalMinor;
  final int? expectedVersion;

  /// null equivale al importe exacto; nunca incluye cambio en el pago aplicado.
  final int? receivedMinor;
}
