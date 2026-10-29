import 'sale_adjustment_json.dart';
import 'sale_adjustment_line.dart';
import 'sale_adjustment_settlement.dart';

class SaleAdjustmentPayload {
  SaleAdjustmentPayload._(
    this.schemaVersion,
    this.kind,
    this.operationId,
    this.eventId,
    this.saleId,
    this.confirmationEventId,
    this.expectedRevision,
    this.previousAdjustmentEventId,
    this.occurredAtMs,
    this.utcOffsetMinutes,
    this.businessDate,
    this.reason,
    this.currency,
    this.totalMinor,
    this.settlement,
    this.lines,
    this.dependencyEventIds,
  );
  final int schemaVersion;
  final String kind;
  final String operationId;
  final String eventId;
  final String saleId;
  final String confirmationEventId;
  final int expectedRevision;
  final String? previousAdjustmentEventId;
  final int occurredAtMs;
  final int utcOffsetMinutes;
  final String businessDate;
  final String reason;
  final String currency;
  final int totalMinor;
  final SaleAdjustmentSettlement settlement;
  final List<SaleAdjustmentLine> lines;
  final List<String> dependencyEventIds;
  factory SaleAdjustmentPayload.fromJson(Object? value) {
    final j = adjustmentObject(value, [
      'schema_version',
      'kind',
      'operation_id',
      'event_id',
      'sale_id',
      'confirmation_event_id',
      'expected_revision',
      'previous_adjustment_event_id',
      'occurred_at_ms',
      'utc_offset_minutes',
      'business_date',
      'reason',
      'currency',
      'total_minor',
      'settlement',
      'lines',
      'dependency_event_ids',
    ]);
    return SaleAdjustmentPayload._(
      adjustmentInt(j['schema_version'], 1),
      adjustmentChoice(j['kind'], ['void', 'return']),
      adjustmentId(j['operation_id']),
      adjustmentId(j['event_id']),
      adjustmentId(j['sale_id']),
      adjustmentId(j['confirmation_event_id']),
      adjustmentInt(j['expected_revision']),
      j['previous_adjustment_event_id'] == null
          ? null
          : adjustmentId(j['previous_adjustment_event_id']),
      adjustmentInt(j['occurred_at_ms'], 1),
      adjustmentOffset(j['utc_offset_minutes']),
      adjustmentText(j['business_date']),
      adjustmentText(j['reason']),
      adjustmentChoice(j['currency'], ['MXN']),
      adjustmentInt(j['total_minor']),
      SaleAdjustmentSettlement.fromJson(j['settlement']),
      adjustmentList(j['lines'], SaleAdjustmentLine.fromJson),
      adjustmentList(j['dependency_event_ids'], adjustmentId),
    );
  }
  Map<String, Object?> toJson() => {
    'schema_version': schemaVersion,
    'kind': kind,
    'operation_id': operationId,
    'event_id': eventId,
    'sale_id': saleId,
    'confirmation_event_id': confirmationEventId,
    'expected_revision': expectedRevision,
    'previous_adjustment_event_id': previousAdjustmentEventId,
    'occurred_at_ms': occurredAtMs,
    'utc_offset_minutes': utcOffsetMinutes,
    'business_date': businessDate,
    'reason': reason,
    'currency': currency,
    'total_minor': totalMinor,
    'settlement': settlement.toJson(),
    'lines': lines.map((v) => v.toJson()).toList(),
    'dependency_event_ids': dependencyEventIds,
  };
}
