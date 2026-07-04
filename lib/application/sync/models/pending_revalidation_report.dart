class PendingRevalidationReport {
  const PendingRevalidationReport({
    required this.checked,
    required this.conflicts,
  });

  const PendingRevalidationReport.empty() : checked = 0, conflicts = 0;

  final int checked;
  final int conflicts;
}
