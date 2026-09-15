class PendingConflict {
  const PendingConflict(
    this.reason, {
    this.officialChangedFields = const {},
    this.officialCategoryIds = const {},
  });

  final String reason;
  final Set<String> officialChangedFields;
  final Set<String> officialCategoryIds;
}
