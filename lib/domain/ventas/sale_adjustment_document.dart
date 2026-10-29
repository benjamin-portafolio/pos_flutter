import 'sale_adjustment_status.dart';

/// Read contract for session 2. Official state excludes rejected physical
/// operations; the local difference remains explicit and auditable.
class SaleAdjustmentDocument {
  SaleAdjustmentDocument({
    required this.operationId,
    required this.eventId,
    required this.saleId,
    required this.businessDate,
    required this.reason,
    required this.userId,
    required this.deviceId,
    required this.occurredAt,
    required this.amountMinor,
    required this.method,
    required this.settlementAction,
    required this.deliveryStatus,
    required this.officialStatus,
    required this.localStatus,
    required this.officialRevision,
    required this.localRevision,
    this.incidentId,
    this.settlementReference,
    this.cashSessionId,
    this.resolutionEventId,
    required List<
      ({
        String saleItemId,
        int quantityAtomic,
        int amountMinor,
        int? recoveredCostMinor,
        String destination,
      })
    >
    lines,
    required List<String> physicalEffectIds,
  }) : lines = List.unmodifiable(lines),
       physicalEffectIds = List.unmodifiable(physicalEffectIds);
  final String operationId,
      eventId,
      saleId,
      businessDate,
      reason,
      userId,
      deviceId,
      deliveryStatus,
      method,
      settlementAction;
  final DateTime occurredAt;
  final int amountMinor, officialRevision, localRevision;
  final SaleAdjustmentStatus officialStatus, localStatus;
  final String? incidentId,
      settlementReference,
      cashSessionId,
      resolutionEventId;
  final List<
    ({
      String saleItemId,
      int quantityAtomic,
      int amountMinor,
      int? recoveredCostMinor,
      String destination,
    })
  >
  lines;
  final List<String> physicalEffectIds;
}
