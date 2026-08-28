class AjustarExistenciaInventarioCommand {
  const AjustarExistenciaInventarioCommand({
    required this.inventoryItemId,
    required this.quantityDeltaAtomic,
    required this.reason,
  });

  final String inventoryItemId;
  final int quantityDeltaAtomic;
  final String reason;
}
