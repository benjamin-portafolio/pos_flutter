/// Transport result contract for sessions 7–9. Physical effects survive terminal
/// outcomes. Duplicate carries the original result, including conflict/rejected.
class SaleAdjustmentOutcome {
  const SaleAdjustmentOutcome({
    required this.eventId,
    required this.operationId,
    required this.status,
    this.originalStatus,
    this.serverSequence,
    this.reason,
    this.winnerEventId,
    this.blockedByEventId,
  });
  final String eventId, operationId;
  final SaleAdjustmentOutcomeStatus status;
  final SaleAdjustmentOutcomeStatus? originalStatus;
  final int? serverSequence;
  final String? reason, winnerEventId, blockedByEventId;
}

enum SaleAdjustmentOutcomeStatus {
  pending,
  accepted,
  duplicate,
  conflict,
  rejected,
}
