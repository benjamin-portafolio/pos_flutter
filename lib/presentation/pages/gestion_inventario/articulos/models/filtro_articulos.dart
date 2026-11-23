class FiltroArticulos {
  const FiltroArticulos({
    this.categoryIds = const <String>{},
    this.includeUncategorized = false,
    this.supplierIds = const <String>{},
  });

  final Set<String> categoryIds;
  final bool includeUncategorized;
  final Set<String> supplierIds;

  int get appliedCount =>
      categoryIds.length + supplierIds.length + (includeUncategorized ? 1 : 0);

  bool get isEmpty => appliedCount == 0;

  FiltroArticulos withCategory(String categoryId, {required bool selected}) {
    final nextIds = Set<String>.of(categoryIds);
    selected ? nextIds.add(categoryId) : nextIds.remove(categoryId);
    return FiltroArticulos(
      categoryIds: Set.unmodifiable(nextIds),
      includeUncategorized: includeUncategorized,
      supplierIds: supplierIds,
    );
  }

  FiltroArticulos withUncategorized({required bool selected}) {
    return FiltroArticulos(
      categoryIds: categoryIds,
      includeUncategorized: selected,
      supplierIds: supplierIds,
    );
  }

  FiltroArticulos withSupplier(String supplierId, {required bool selected}) {
    final nextIds = Set<String>.of(supplierIds);
    selected ? nextIds.add(supplierId) : nextIds.remove(supplierId);
    return FiltroArticulos(
      categoryIds: categoryIds,
      includeUncategorized: includeUncategorized,
      supplierIds: Set.unmodifiable(nextIds),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FiltroArticulos &&
        other.supplierIds.length == supplierIds.length &&
        other.supplierIds.containsAll(supplierIds) &&
        other.includeUncategorized == includeUncategorized &&
        other.categoryIds.length == categoryIds.length &&
        other.categoryIds.containsAll(categoryIds);
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(categoryIds),
    Object.hashAllUnordered(supplierIds),
    includeUncategorized,
  );
}
