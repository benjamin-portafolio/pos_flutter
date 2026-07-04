class SyncPullReport {
  const SyncPullReport({
    required this.total,
    required this.lastCursor,
    required this.hasMore,
  });

  const SyncPullReport.empty({required this.lastCursor})
    : total = 0,
      hasMore = false;

  final int total;
  final int lastCursor;
  final bool hasMore;
}
