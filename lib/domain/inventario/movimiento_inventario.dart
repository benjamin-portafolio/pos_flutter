class MovimientoInventario {
  const MovimientoInventario({
    required this.id,
    this.saleId,
    required this.inventoryItemId,
    required this.saleItemId,
    required this.eventId,
    required this.reversalOfMovementId,
    required this.movementType,
    required this.quantityDeltaAtomic,
    required this.totalCostMinor,
    required this.reason,
    required this.createdAtLocal,
    required this.serverSequence,
  });

  final String id;

  /// Venta de origen, resuelta desde el renglón cuando esté disponible.
  final String? saleId;
  final String inventoryItemId;
  final String? saleItemId;
  final String eventId;
  final String? reversalOfMovementId;
  final String movementType;
  final int quantityDeltaAtomic;
  final int? totalCostMinor;
  final String? reason;
  final DateTime createdAtLocal;
  final int? serverSequence;
}
