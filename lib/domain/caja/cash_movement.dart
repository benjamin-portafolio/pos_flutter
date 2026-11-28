class CashMovement {
  const CashMovement({
    required this.id,
    required this.eventId,
    required this.direction,
    required this.amountMinor,
    required this.sourceType,
    required this.sourceId,
    required this.deliveryStatus,
    required this.createdAt,
    required this.localSequence,
    this.saleId,
    this.rejectionReason,
  });
  final String id, eventId, direction, sourceType, sourceId, deliveryStatus;
  final int amountMinor;

  /// Fecha del evento de origen; puede faltar en evidencia histórica incompleta.
  final DateTime? createdAt;

  /// Desempata operaciones registradas en el mismo instante.
  final int? localSequence;

  /// Venta correspondiente al pago, cuando el origen es un cobro de venta.
  final String? saleId;
  final String? rejectionReason;
}
