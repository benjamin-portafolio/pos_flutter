import 'package:drift/drift.dart';
import '../../domain/creditos/account_entry.dart';
import '../../domain/creditos/customer_account.dart';
import '../../domain/repositories/customer_account_repository.dart';
import '../local/drift/app_database.dart';

class CustomerAccountRepositoryImpl implements CustomerAccountRepository {
  CustomerAccountRepositoryImpl(this.db);
  final AppDatabase db;
  static const entriesSql = r"""
    SELECT c.id, c.created_event_id AS event_id, c.amount_minor - COALESCE((SELECT SUM(r.amount_minor) FROM sale_credit_reductions r JOIN sale_adjustments a ON a.id=r.operation_id WHERE r.credit_id=c.id AND a.commercial_active=1),0) AS amount_minor, c.occurred_at_ms,
      c.cliente_id, c.sale_id, 0 AS is_payment, NULL AS method, NULL AS reference,
      e.delivery_status, e.rejection_reason, e.user_id, e.device_id, 0 AS is_reconciliation
    FROM credit_sales c LEFT JOIN events e ON e.event_id = c.created_event_id
    UNION ALL
    SELECT p.id, p.created_event_id, p.amount_minor, p.occurred_at_ms,
      p.cliente_id, NULL, 1, p.method, p.reference,
      e.delivery_status, e.rejection_reason, e.user_id, e.device_id, 0
    FROM customer_payments p LEFT JOIN events e ON e.event_id = p.created_event_id
    UNION ALL
    SELECT r.effect_id, r.event_id, abs(r.delta), CAST(json_extract(r.payload_json,'$.occurred_at_ms') AS INTEGER),
      r.target_id, NULL, CASE WHEN r.delta>0 THEN 1 ELSE 0 END, 'reconciliation', NULL,
      e.delivery_status, e.rejection_reason, e.user_id, e.device_id, 1
    FROM sale_reconciliation_effects r JOIN events e ON e.event_id=r.event_id
    WHERE r.ledger='credit' AND e.delivery_status='delivered'
  """;
  AccountEntry _entry(QueryRow row) => AccountEntry(
    id: row.read<String>('id'),
    eventId: row.read<String>('event_id'),
    amountMinor: row.read<int>('amount_minor'),
    occurredAtMs: row.read<int>('occurred_at_ms'),
    isReconciliation: row.read<int>('is_reconciliation') == 1,
    isPayment: row.read<int>('is_payment') == 1,
    saleId: row.readNullable<String>('sale_id'),
    method: row.readNullable<String>('method'),
    reference: row.readNullable<String>('reference'),
    deliveryStatus: row.read<String>('delivery_status'),
    reason: row.readNullable<String>('rejection_reason'),
    userId: row.read<String>('user_id'),
    deviceId: row.read<String>('device_id'),
  );
  @override
  Stream<CustomerAccount> watchAccount(String clienteId) => db
      .customSelect(
        'SELECT * FROM ($entriesSql) WHERE cliente_id = ?',
        variables: [Variable(clienteId)],
        readsFrom: {
          db.creditSales,
          db.customerPayments,
          db.events,
          db.saleCreditReductions,
          db.saleReconciliationEffects,
          db.saleAdjustments,
        },
      )
      .watch()
      .map((rows) => CustomerAccount(rows.map(_entry)));
}
