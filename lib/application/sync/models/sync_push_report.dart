class SyncPushReport {
  const SyncPushReport({
    required this.total,
    required this.synced,
    required this.rejected,
    required this.conflicts,
    required this.pending,
  });

  const SyncPushReport.empty()
    : total = 0,
      synced = 0,
      rejected = 0,
      conflicts = 0,
      pending = 0;

  final int total;
  final int synced;
  final int rejected;
  final int conflicts;
  final int pending;
}
