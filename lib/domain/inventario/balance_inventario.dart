class BalanceInventario {
  const BalanceInventario({
    required this.inventoryItemId,
    required this.quantityOnHandAtomic,
    required this.quantityAvailableAtomic,
    required this.lastEventId,
    required this.lastServerSequence,
  });

  final String inventoryItemId;
  final int quantityOnHandAtomic;
  final int quantityAvailableAtomic;
  final String lastEventId;
  final int? lastServerSequence;
}
