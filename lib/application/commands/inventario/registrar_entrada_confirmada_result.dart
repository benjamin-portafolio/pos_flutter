/// Identidades devueltas por el comando dentro de la transacción de recepción.
class RegistrarEntradaConfirmadaResult {
  const RegistrarEntradaConfirmadaResult({
    required this.inventoryItemId,
    required this.eventId,
    required this.movementId,
  });

  final String inventoryItemId;
  final String eventId;
  final String movementId;

  Map<String, Object?> toJson() => {
    'inventory_item_id': inventoryItemId,
    'event_id': eventId,
    'movement_id': movementId,
  };

  factory RegistrarEntradaConfirmadaResult.fromJson(
    Map<String, Object?> json,
  ) => RegistrarEntradaConfirmadaResult(
    inventoryItemId: json['inventory_item_id'] as String,
    eventId: json['event_id'] as String,
    movementId: json['movement_id'] as String,
  );
}
