import 'package:drift/drift.dart';

import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/payloads/saldo_cuenta_inicial_declarado_payload.dart';
import '../../../application/sync/projections/account_balance_baseline_projection.dart';
import '../../../application/sync/projections/account_balance_baseline_projection_store.dart';
import 'app_database.dart';

class DriftAccountBalanceBaselineProjectionStore
    implements AccountBalanceBaselineProjectionStore {
  DriftAccountBalanceBaselineProjectionStore(this.db);
  final AppDatabase db;

  @override
  Future<T> atomic<T>(Future<T> Function() action) => db.transaction(action);

  AccountBalanceBaselineProjection _map(AccountBalanceBaselineRow r) =>
      AccountBalanceBaselineProjection(
        id: r.id,
        active: r.active,
        version: r.version,
        createdEventId: r.createdEventId,
        lastEventId: r.lastEventId,
        lastServerSequence: r.lastServerSequence,
        deviceId: r.deviceId,
        declaredByUserId: r.declaredByUserId,
        amountMinor: r.amountMinor,
        asOfMs: r.asOfMs,
      );

  @override
  Future<AccountBalanceBaselineProjection?> find(String id) async {
    final r = await (db.select(
      db.accountBalanceBaselines,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _map(r);
  }

  @override
  Future<AccountBalanceBaselineProjection?> only() async {
    final r = await (db.select(db.accountBalanceBaselines)
          ..limit(1))
        .getSingleOrNull();
    return r == null ? null : _map(r);
  }

  @override
  Future<AccountBalanceBaselineProjection?> otherThan(
    String createdEventId,
  ) async {
    final r = await (db.select(db.accountBalanceBaselines)
          ..where((t) => t.createdEventId.isNotValue(createdEventId))
          ..limit(1))
        .getSingleOrNull();
    return r == null ? null : _map(r);
  }

  @override
  Future<void> insertBaseline(
    SyncEvent e,
    SaldoCuentaInicialDeclaradoPayload p,
  ) async {
    await db
        .into(db.accountBalanceBaselines)
        .insert(
          AccountBalanceBaselinesCompanion.insert(
            id: e.aggregateId,
            deviceId: e.deviceId,
            declaredByUserId: e.userId,
            amountMinor: p.amountMinor,
            asOfMs: p.asOfMs,
            createdEventId: Value(e.eventId),
            lastEventId: Value(e.eventId),
            lastServerSequence: Value(e.serverSequence),
          ),
        );
  }

  @override
  Future<void> acknowledge(String eventId, int sequence) async {
    await db.customUpdate(
      'UPDATE account_balance_baselines SET last_server_sequence=? WHERE (created_event_id=? OR last_event_id=?) AND (last_server_sequence IS NULL OR last_server_sequence<?)',
      variables: [
        Variable(sequence),
        Variable(eventId),
        Variable(eventId),
        Variable(sequence),
      ],
      updates: {db.accountBalanceBaselines},
    );
  }
}
