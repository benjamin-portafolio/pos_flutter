import 'sync_event.dart';
import '../payloads/sale_adjustment_payload.dart';
import '../payloads/sale_reconciliation_effect.dart';

class SaleIncidentDetails {
  const SaleIncidentDetails({
    required this.id,
    required this.saleId,
    required this.reason,
    required this.loser,
    required this.winnerEventId,
    required this.officialBaseEventId,
    required this.officialRevision,
    required this.evidence,
    this.resolutionEventId,
    this.blockedByEventId,
    this.winner,
    this.recordedRecoveries = const [],
    this.attempts = const [],
  });
  final String id, saleId, reason;
  final String? winnerEventId,
      resolutionEventId,
      officialBaseEventId,
      blockedByEventId;
  final int officialRevision;
  final SaleAdjustmentPayload loser;
  final SaleAdjustmentPayload? winner;
  final List<SaleReconciliationEffect> evidence;
  final List<SaleReconciliationEffect> recordedRecoveries;
  final List<SyncEvent> attempts;
}
