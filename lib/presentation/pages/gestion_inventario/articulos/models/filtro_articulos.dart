class FiltroArticulos {
  const FiltroArticulos({
    this.categoryIds = const <String>{},
    this.includeUncategorized = false,
  });

  final Set<String> categoryIds;
  final bool includeUncategorized;

  int get appliedCount => categoryIds.length + (includeUncategorized ? 1 : 0);

  bool get isEmpty => appliedCount == 0;

  FiltroArticulos withCategory(String categoryId, {required bool selected}) {
    final nextIds = Set<String>.of(categoryIds);
    selected ? nextIds.add(categoryId) : nextIds.remove(categoryId);
    return FiltroArticulos(
      categoryIds: Set.unmodifiable(nextIds),
      includeUncategorized: includeUncategorized,
    );
  }

  FiltroArticulos withUncategorized({required bool selected}) {
    return FiltroArticulos(
      categoryIds: categoryIds,
      includeUncategorized: selected,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FiltroArticulos &&
        other.includeUncategorized == includeUncategorized &&
        other.categoryIds.length == categoryIds.length &&
        other.categoryIds.containsAll(categoryIds);
  }

  @override
  int get hashCode =>
      Object.hashAllUnordered([...categoryIds, includeUncategorized]);
}
