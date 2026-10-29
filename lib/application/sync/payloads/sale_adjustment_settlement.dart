import 'sale_adjustment_json.dart';
import 'cash_binding_payload.dart';

class SaleAdjustmentSettlement {
  SaleAdjustmentSettlement._(
    this.method,
    this.paymentId,
    this.clienteId,
    this.action,
    this.reference,
    this.cashEnabled,
    this.cash,
  );
  final String method;
  final String? paymentId;
  final String? clienteId;
  final String action;
  final String? reference;
  final bool cashEnabled;
  final CashBindingPayload? cash;
  factory SaleAdjustmentSettlement.fromJson(Object? value) {
    final j = adjustmentObject(value, [
      'method',
      'payment_id',
      'cliente_id',
      'action',
      'reference',
      'cash_enabled',
      'cash',
    ]);
    return SaleAdjustmentSettlement._(
      adjustmentChoice(j['method'], ['cash', 'transfer', 'credit']),
      j['payment_id'] == null ? null : adjustmentId(j['payment_id']),
      j['cliente_id'] == null ? null : adjustmentId(j['cliente_id']),
      adjustmentChoice(j['action'], [
        'refund_completed',
        'unreceived_correction',
        'credit_reduction',
        'no_money',
      ]),
      j['reference'] == null ? null : adjustmentText(j['reference']),
      adjustmentBool(j['cash_enabled']),
      j['cash'] == null
          ? null
          : CashBindingPayload.optional(
              adjustmentObject(j['cash'], [
                'session_id',
                'opening_event_id',
                'movement_id',
              ]),
              "cash",
              1,
            ),
    );
  }
  Map<String, Object?> toJson() => {
    'method': method,
    'payment_id': paymentId,
    'cliente_id': clienteId,
    'action': action,
    'reference': reference,
    'cash_enabled': cashEnabled,
    'cash': cash?.toJson(),
  };
}
