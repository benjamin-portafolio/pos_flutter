class VariantTrackingBalance {
  const VariantTrackingBalance({
    required this.quantityOnHandAtomic,
    required this.quantityAvailableAtomic,
  });

  final int quantityOnHandAtomic;
  final int quantityAvailableAtomic;

  bool get isZero => quantityOnHandAtomic == 0 && quantityAvailableAtomic == 0;
}
