import 'package:drift/drift.dart';
import '../../domain/creditos/account_entry.dart';
import '../../domain/creditos/customer_account.dart';
import '../../domain/repositories/customer_account_repository.dart';
import '../local/drift/app_database.dart';

class CustomerAccountRepositoryImpl implements CustomerAccountRepository {
  CustomerAccountRepositoryImpl(this.db);
  final AppDatabase db;
  static const _query = """
    SELECT c.id, c.created_event_id AS event_id, c.amount_minor, c.occurred_at_ms,
      c.cliente_id, c.sale_id, 0 AS is_payment, NULL AS method, NULL AS reference,
      e.delivery_status, e.rejection_reason, e.user_id, e.device_id
    FROM credit_sales c JOIN events e ON e.event_id = c.created_event_id
    UNION ALL
    SELECT p.id, p.created_event_id, p.amount_minor, p.occurred_at_ms,
      p.cliente_id, NULL, 1, p.method, p.reference,
      e.delivery_status, e.rejection_reason, e.user_id, e.device_id
    FROM customer_payments p JOIN events e ON e.event_id = p.created_event_id
  """;
  AccountEntry _entry(QueryRow row) => AccountEntry(
    id: row.read<String>('id'),
    eventId: row.read<String>('event_id'),
    amountMinor: row.read<int>('amount_minor'),
    occurredAtMs: row.read<int>('occurred_at_ms'),
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
        'SELECT * FROM ($_query) WHERE cliente_id = ?',
        variables: [Variable(clienteId)],
        readsFrom: {db.creditSales, db.customerPayments, db.events},
      )
      .watch()
      .map((rows) => CustomerAccount(rows.map(_entry)));
  @override
  Stream<List<AccountEntry>> watchPayments() => db
      .customSelect(
        'SELECT * FROM ($_query) WHERE is_payment = 1',
        readsFrom: {db.creditSales, db.customerPayments, db.events},
      )
      .watch()
      .map((rows) => rows.map(_entry).toList());
}
