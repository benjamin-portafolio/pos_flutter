import 'sale_adjustment_json.dart';

/// One durable ledger effect, signed in atomic units (stock) or minor units (money).
class SaleReconciliationEffect {
  SaleReconciliationEffect._(
    this.effectId,
    this.ledger,
    this.targetId,
    this.delta,
    this.occurredAtMs,
    this.cashSessionId,
    this.openingEventId,
    this.utcOffsetMinutes,
    this.businessDate,
  );
  final String effectId, ledger, targetId;
  final int delta, occurredAtMs, utcOffsetMinutes;
  final String businessDate;
  final String? cashSessionId, openingEventId;
  factory SaleReconciliationEffect.fromJson(Object? value) {
    final j = adjustmentObject(value, [
      'effect_id',
      'ledger',
      'target_id',
      'delta',
      'occurred_at_ms',
      'cash_session_id',
      'opening_event_id',
      'utc_offset_minutes',
      'business_date',
    ]);
    final delta = j['delta'];
    if (delta is! int || delta == 0 || delta.abs() > 9007199254740991) {
      throw const FormatException('Delta inválido.');
    }
    final ledger = adjustmentChoice(j['ledger'], [
      'stock',
      'cash',
      'credit',
      'transfer',
    ]);
    final session = j['cash_session_id'] == null
        ? null
        : adjustmentId(j['cash_session_id']);
    final opening = j['opening_event_id'] == null
        ? null
        : adjustmentId(j['opening_event_id']);
    if ((session == null) != (opening == null) ||
        (ledger != 'cash' && session != null)) {
      throw const FormatException('Caja inconsistente.');
    }
    adjustmentBusinessDate(
      adjustmentInt(j['occurred_at_ms'], 1),
      adjustmentOffset(j['utc_offset_minutes']),
      adjustmentText(j['business_date']),
    );
    return SaleReconciliationEffect._(
      adjustmentId(j['effect_id']),
      ledger,
      adjustmentId(j['target_id']),
      delta,
      adjustmentInt(j['occurred_at_ms'], 1),
      session,
      opening,
      adjustmentOffset(j['utc_offset_minutes']),
      adjustmentText(j['business_date']),
    );
  }
  Map<String, Object?> toJson() => {
    'effect_id': effectId,
    'ledger': ledger,
    'target_id': targetId,
    'delta': delta,
    'occurred_at_ms': occurredAtMs,
    'cash_session_id': cashSessionId,
    'opening_event_id': openingEventId,
    'utc_offset_minutes': utcOffsetMinutes,
    'business_date': businessDate,
  };
}
