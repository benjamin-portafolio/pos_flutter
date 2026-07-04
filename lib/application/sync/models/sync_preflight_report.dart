class SyncPreflightReport {
  const SyncPreflightReport({
    required this.skipped,
    required this.pendingCount,
    required this.impactingEvents,
    required this.preflightSequence,
    required this.hasMore,
    required this.requiresFullPullBeforePush,
    required this.reason,
    required this.localConflicts,
  });

  const SyncPreflightReport.skipped({
    required this.reason,
    this.pendingCount = 0,
    this.localConflicts = 0,
  }) : skipped = true,
       impactingEvents = 0,
       preflightSequence = null,
       hasMore = false,
       requiresFullPullBeforePush = false;

  final bool skipped;
  final int pendingCount;
  final int impactingEvents;
  final int? preflightSequence;
  final bool hasMore;
  final bool requiresFullPullBeforePush;
  final String? reason;
  final int localConflicts;
}
