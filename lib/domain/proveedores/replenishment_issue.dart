class ReplenishmentIssue {
  const ReplenishmentIssue(
    this.productId,
    this.variantId,
    this.name,
    this.reason,
  );
  final String productId, variantId, name, reason;
}
