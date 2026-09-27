import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/payloads/caja_abierta_payload.dart';
import '../../../application/sync/payloads/caja_cerrada_payload.dart';
import '../../../application/sync/payloads/cash_binding_payload.dart';
import '../../../application/sync/payloads/cash_movement_evidence.dart';
import '../../../application/sync/projections/cash_projection_store.dart';
import '../../../application/sync/projections/cash_session_projection.dart';
import 'app_database.dart';

class DriftCashProjectionStore implements CashProjectionStore {
  DriftCashProjectionStore(this.db);
  final AppDatabase db;
  @override
  Future<T> atomic<T>(Future<T> Function() action) => db.transaction(action);
  CashSessionProjection _map(CashSessionRow r) => CashSessionProjection(
    id: r.id,
    active: r.active,
    version: r.version,
    createdEventId: r.createdEventId,
    lastEventId: r.lastEventId,
    lastServerSequence: r.lastServerSequence,
    deviceId: r.deviceId,
    openedByUserId: r.openedByUserId,
    status: r.status,
    openedAtMs: r.openedAtMs,
    openingMinor: r.openingMinor,
    closedByUserId: r.closedByUserId,
    previousCloseEventId: r.previousCloseEventId,
    close: r.closeSnapshot == null
        ? null
        : CajaCerradaPayload.fromJson(
            Map<String, Object?>.from(jsonDecode(r.closeSnapshot!) as Map),
          ),
  );
  @override
  Future<CashSessionProjection?> find(String id) async {
    final r = await (db.select(
      db.cashSessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : _map(r);
  }

  @override
  Future<CashSessionProjection?> current(String deviceId) async {
    final r =
        await (db.select(db.cashSessions)..where(
              (t) => t.deviceId.equals(deviceId) & t.status.equals('open'),
            ))
            .getSingleOrNull();
    return r == null ? null : _map(r);
  }

  @override
  Future<CashSessionProjection?> latest(String deviceId) async {
    final rows = await db
        .customSelect(
          'SELECT s.id FROM cash_sessions s JOIN events e ON e.event_id=s.created_event_id WHERE s.device_id=? ORDER BY e.local_sequence DESC LIMIT 1',
          variables: [Variable(deviceId)],
          readsFrom: {db.cashSessions, db.events},
        )
        .get();
    return rows.isEmpty ? null : find(rows.single.read<String>('id'));
  }

  @override
  Future<List<CashMovementEvidence>> movements(String sessionId) async =>
      (await (db.select(db.cashMovements)
                ..where((t) => t.sessionId.equals(sessionId))
                ..orderBy([(t) => OrderingTerm.asc(t.id)]))
              .get())
          .map(
            (r) => CashMovementEvidence(
              movementId: r.id,
              eventId: r.createdEventId!,
              direction: r.direction,
              amountMinor: r.amountMinor,
              sourceType: r.salePaymentId != null
                  ? 'sale_payment'
                  : r.customerPaymentId != null
                  ? 'customer_payment'
                  : 'financial_entry',
              sourceId:
                  (r.salePaymentId ??
                  r.customerPaymentId ??
                  r.financialEntryId)!,
            ),
          )
          .toList();
  @override
  Future<void> insertSession(SyncEvent e, CajaAbiertaPayload p) async {
    await db
        .into(db.cashSessions)
        .insert(
          CashSessionsCompanion.insert(
            id: e.aggregateId,
            deviceId: e.deviceId,
            openedByUserId: e.userId,
            status: 'open',
            openedAtMs: p.openedAtMs,
            openingMinor: p.openingMinor,
            previousCloseEventId: Value(p.previousCloseEventId),
            createdEventId: Value(e.eventId),
            lastEventId: Value(e.eventId),
            lastServerSequence: Value(e.serverSequence),
          ),
        );
  }

  @override
  Future<void> closeSession(SyncEvent e, CajaCerradaPayload p) async {
    await (db.update(
      db.cashSessions,
    )..where((t) => t.id.equals(e.aggregateId))).write(
      CashSessionsCompanion(
        status: const Value('closed'),
        closedByUserId: Value(e.userId),
        closedAtMs: Value(p.closedAtMs),
        countedMinor: Value(p.countedMinor),
        incomeMinor: Value(p.incomeMinor),
        expenseMinor: Value(p.expenseMinor),
        expectedMinor: Value(p.expectedMinor),
        differenceMinor: Value(p.differenceMinor),
        notes: Value(p.notes),
        closeSnapshot: Value(jsonEncode(p.toJson())),
        lastEventId: Value(e.eventId),
        lastServerSequence: Value(e.serverSequence),
        version: const Value(2),
      ),
    );
  }

  @override
  Future<void> insertMovement(
    SyncEvent e,
    CashBindingPayload b,
    CashMovementEvidence p,
  ) async {
    final table = switch (p.sourceType) {
      'sale_payment' => 'sale_payments',
      'customer_payment' => 'customer_payments',
      _ => 'financial_entries',
    };
    final source = await db
        .customSelect(
          'SELECT * FROM $table WHERE id=?',
          variables: [Variable(p.sourceId)],
        )
        .getSingle();
    if (source.read<String>('method') != 'cash' ||
        source.read<int>('amount_minor') != p.amountMinor ||
        source.read<String>('created_event_id') != e.eventId ||
        (p.sourceType == 'financial_entry' &&
            source.read<String>('direction') != p.direction)) {
      throw StateError('El origen real no coincide con el movimiento.');
    }
    await db
        .into(db.cashMovements)
        .insert(
          CashMovementsCompanion.insert(
            id: p.movementId,
            sessionId: b.sessionId,
            direction: p.direction,
            amountMinor: p.amountMinor,
            salePaymentId: Value(
              p.sourceType == 'sale_payment' ? p.sourceId : null,
            ),
            customerPaymentId: Value(
              p.sourceType == 'customer_payment' ? p.sourceId : null,
            ),
            financialEntryId: Value(
              p.sourceType == 'financial_entry' ? p.sourceId : null,
            ),
            createdEventId: Value(e.eventId),
            lastEventId: Value(e.eventId),
            lastServerSequence: Value(e.serverSequence),
          ),
        );
  }

  @override
  Future<void> acknowledge(String eventId, int sequence) async {
    for (final table in ['cash_sessions', 'cash_movements']) {
      await db.customUpdate(
        'UPDATE $table SET last_server_sequence=? WHERE (created_event_id=? OR last_event_id=?) AND (last_server_sequence IS NULL OR last_server_sequence<?)',
        variables: [
          Variable(sequence),
          Variable(eventId),
          Variable(eventId),
          Variable(sequence),
        ],
        updates: table == 'cash_sessions'
            ? {db.cashSessions}
            : {db.cashMovements},
      );
    }
  }
}
