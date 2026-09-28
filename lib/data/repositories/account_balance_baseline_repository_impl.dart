import '../../domain/cuenta/account_balance_baseline.dart';
import '../../domain/repositories/account_balance_baseline_repository.dart';
import '../local/drift/app_database.dart';

/// El estado de entrega se resuelve por join a `events` por `last_event_id`, la
/// misma forma que `CashRepositoryImpl` usa para caja. Por eso la tabla
/// necesita los `CommonFields`: sin `last_event_id` no hay chip de estado.
class AccountBalanceBaselineRepositoryImpl
    implements AccountBalanceBaselineRepository {
  AccountBalanceBaselineRepositoryImpl(this.db);
  final AppDatabase db;

  @override
  Stream<AccountBalanceBaseline?> watchBaseline() => db
      .customSelect(
        'SELECT b.*,e.delivery_status,e.rejection_reason FROM account_balance_baselines b JOIN events e ON e.event_id=b.last_event_id',
        readsFrom: {db.accountBalanceBaselines, db.events},
      )
      .watch()
      .asyncMap(
        (rows) async => rows.isEmpty
            ? null
            : AccountBalanceBaseline(
                id: rows.single.read<String>('id'),
                deviceId: rows.single.read<String>('device_id'),
                declaredByUserId: rows.single.read<String>(
                  'declared_by_user_id',
                ),
                amountMinor: rows.single.read<int>('amount_minor'),
                asOfMs: rows.single.read<int>('as_of_ms'),
                createdEventId: rows.single.read<String>('created_event_id'),
                lastEventId: rows.single.read<String>('last_event_id'),
                deliveryStatus: rows.single.read<String>('delivery_status'),
                rejectionReason: rows.single.readNullable<String>(
                  'rejection_reason',
                ),
              ),
      );
}
