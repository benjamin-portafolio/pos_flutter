import 'dart:convert';
import '../local_event_store.dart';
import 'sale_adjustment_json.dart';
import 'sale_reconciliation_effect.dart';

/// Independent regularization, never another accepted return quantity or a payment.
class OperacionVentaConciliadaPayload {
  OperacionVentaConciliadaPayload._(
    this.operationId,
    this.eventId,
    this.incidentId,
    this.saleId,
    this.loserEventId,
    this.winnerEventId,
    this.officialBaseEventId,
    this.expectedRevision,
    this.occurredAtMs,
    this.reason,
    this.preservedEffects,
    this.recoveryEffects,
    this.utcOffsetMinutes,
    this.businessDate,
  );
  static const aggregateType = 'sale';
  static const eventType = 'operacion_venta_conciliada';
  final String operationId,
      eventId,
      incidentId,
      saleId,
      loserEventId,
      winnerEventId,
      officialBaseEventId,
      reason;
  final int expectedRevision, occurredAtMs, utcOffsetMinutes;
  final String businessDate;
  final List<SaleReconciliationEffect> preservedEffects, recoveryEffects;
  factory OperacionVentaConciliadaPayload.fromJson(Map<String, Object?> value) {
    final j = adjustmentObject(value, [
      'schema_version',
      'operation_id',
      'event_id',
      'incident_id',
      'sale_id',
      'loser_event_id',
      'winner_event_id',
      'official_base_event_id',
      'expected_revision',
      'occurred_at_ms',
      'reason',
      'preserved_effects',
      'recovery_effects',
      'utc_offset_minutes',
      'business_date',
    ]);
    if (j['schema_version'] != 1) {
      throw const FormatException('Versión inválida.');
    }
    final p = OperacionVentaConciliadaPayload._(
      adjustmentId(j['operation_id']),
      adjustmentId(j['event_id']),
      adjustmentId(j['incident_id']),
      adjustmentId(j['sale_id']),
      adjustmentId(j['loser_event_id']),
      adjustmentId(j['winner_event_id']),
      adjustmentId(j['official_base_event_id']),
      adjustmentInt(j['expected_revision']),
      adjustmentInt(j['occurred_at_ms'], 1),
      adjustmentText(j['reason']),
      adjustmentList(j['preserved_effects'], SaleReconciliationEffect.fromJson),
      adjustmentList(j['recovery_effects'], SaleReconciliationEffect.fromJson),
      adjustmentOffset(j['utc_offset_minutes']),
      adjustmentText(j['business_date']),
    );
    adjustmentBusinessDate(p.occurredAtMs, p.utcOffsetMinutes, p.businessDate);
    final effects = [...p.preservedEffects, ...p.recoveryEffects];
    if (p.eventId == p.operationId ||
        p.loserEventId == p.winnerEventId ||
        effects.map((e) => e.effectId).toSet().length != effects.length ||
        p.recoveryEffects.any((e) => e.occurredAtMs > p.occurredAtMs)) {
      throw const FormatException('Conciliación inválida.');
    }
    if (effects.any(
      (e) =>
          e.effectId == p.operationId ||
          e.effectId == p.eventId ||
          e.occurredAtMs > p.occurredAtMs,
    )) {
      throw const FormatException('Identidad/fecha de efecto inválida.');
    }
    return p;
  }

  /// Caller rereads/locks incident, official revision and current recovery cash sessions.
  void validateIncident({
    required String incident,
    required String sale,
    required String loser,
    required String winner,
    required String officialBase,
    required int revision,
    required List<SaleReconciliationEffect> evidence,
    required bool alreadyConsumed,
  }) {
    final actual = {
      for (final e in evidence) e.effectId: jsonEncode(e.toJson()),
    };
    if (alreadyConsumed ||
        incident != incidentId ||
        sale != saleId ||
        loser != loserEventId ||
        winner != winnerEventId ||
        officialBase != officialBaseEventId ||
        revision != expectedRevision ||
        actual.length != preservedEffects.length ||
        preservedEffects.any(
          (e) => actual[e.effectId] != jsonEncode(e.toJson()),
        )) {
      throw const FormatException('Incidencia, evidencia o base obsoleta.');
    }
  }

  List<String> get dependencyEventIds => List.unmodifiable({
    officialBaseEventId,
    winnerEventId,
    for (final e in recoveryEffects)
      if (e.openingEventId != null) e.openingEventId!,
  });
  List<LocalEventRef> get refs => [
    for (final id in {
      ...dependencyEventIds,
      loserEventId,
      for (final e in preservedEffects)
        if (e.openingEventId != null) e.openingEventId!,
    })
      LocalEventRef.uses(refType: 'event', refId: id),
    LocalEventRef.affects(refType: 'sale', refId: saleId),
    LocalEventRef.affects(refType: 'sale_incident', refId: incidentId),
    LocalEventRef.affects(refType: 'sale_reconciliation', refId: operationId),
    for (final e in [...preservedEffects, ...recoveryEffects]) ...[
      LocalEventRef.affects(refType: 'physical_effect', refId: e.effectId),
      LocalEventRef.affects(
        refType: e.ledger == 'stock'
            ? 'inventory_item'
            : e.ledger == 'credit'
            ? 'customer_account'
            : e.ledger == 'cash'
            ? 'cash_movement'
            : 'transfer_adjustment',
        refId: e.targetId,
      ),
      if (e.cashSessionId != null)
        LocalEventRef.uses(refType: 'cash_session', refId: e.cashSessionId!),
    ],
  ];
  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'utc_offset_minutes': utcOffsetMinutes,
    'business_date': businessDate,
    'operation_id': operationId,
    'event_id': eventId,
    'incident_id': incidentId,
    'sale_id': saleId,
    'loser_event_id': loserEventId,
    'winner_event_id': winnerEventId,
    'official_base_event_id': officialBaseEventId,
    'expected_revision': expectedRevision,
    'occurred_at_ms': occurredAtMs,
    'reason': reason,
    'preserved_effects': preservedEffects.map((e) => e.toJson()).toList(),
    'recovery_effects': recoveryEffects.map((e) => e.toJson()).toList(),
  };
}
