import '../../application/sync/payloads/caja_cerrada_payload.dart';
import 'dart:convert';
import '../../application/sync/payloads/operacion_venta_conciliada_payload.dart';
import '../../domain/caja/cash_regularization.dart';
import 'package:drift/drift.dart';
import '../../domain/caja/cash_movement.dart';
import '../../domain/caja/cash_session.dart';
import '../../domain/repositories/cash_repository.dart';
import '../local/drift/app_database.dart';

class CashRepositoryImpl implements CashRepository {
  CashRepositoryImpl(this.db);
  final AppDatabase db;
  @override
  Stream<List<CashSession>> watchSessions() => db
      .customSelect(
        'SELECT s.*,e.delivery_status,e.rejection_reason FROM cash_sessions s JOIN events e ON e.event_id=s.last_event_id ORDER BY s.opened_at_ms DESC,s.id',
        readsFrom: {
          db.cashSessions,
          db.cashMovements,
          db.events,
          db.saleReconciliationEffects,
        },
      )
      .watch()
      .asyncMap((rows) async {
        final sessions = <CashSession>[];
        for (final r in rows) {
          final items = await db
              .customSelect(
                'SELECT m.*,e.delivery_status,e.rejection_reason FROM cash_movements m JOIN events e ON e.event_id=m.created_event_id WHERE m.session_id=? ORDER BY e.local_sequence,m.id',
                variables: [Variable(r.read<String>('id'))],
                readsFrom: {db.cashMovements, db.events},
              )
              .get();
          final regularizations = <CashRegularization>[];
          for (final effect
              in await (db.select(db.saleReconciliationEffects)..where(
                    (t) =>
                        t.ledger.equals('cash') &
                        t.cashSessionId.equals(r.read<String>('id')) &
                        t.appliedLocally.equals(true),
                  ))
                  .get()) {
            final e = await db.eventDao.obtenerEventoPorId(effect.eventId);
            final p = OperacionVentaConciliadaPayload.fromJson(
              Map<String, Object?>.from(jsonDecode(e!.payload) as Map),
            );
            regularizations.add(
              CashRegularization(
                effectId: effect.effectId,
                eventId: effect.eventId,
                deltaMinor: effect.delta,
                isRecovery: p.recoveryEffects.any(
                  (x) => x.effectId == effect.effectId,
                ),
                deliveryStatus: e.deliveryStatus,
                affectsExpected: !items.any(
                  (m) => m.read<String>('id') == effect.effectId,
                ),
              ),
            );
          }
          List<CashMovement>? closedMovements;
          final closeSnapshot = r.readNullable<String>('close_snapshot');
          if (closeSnapshot != null) {
            final close = CajaCerradaPayload.fromJson(
              Map<String, Object?>.from(jsonDecode(closeSnapshot) as Map),
            );
            closedMovements = [];
            for (final m in close.movements) {
              final e = await db.eventDao.obtenerEventoPorId(m.eventId);
              closedMovements.add(
                CashMovement(
                  id: m.movementId,
                  eventId: m.eventId,
                  direction: m.direction,
                  amountMinor: m.amountMinor,
                  sourceType: m.sourceType,
                  sourceId: m.sourceId,
                  deliveryStatus: e?.deliveryStatus ?? 'pending',
                  rejectionReason: e?.rejectionReason,
                ),
              );
            }
          }
          sessions.add(
            CashSession(
              regularizations: regularizations,
              closedMovements: closedMovements,
              id: r.read<String>('id'),
              deviceId: r.read<String>('device_id'),
              openedByUserId: r.read<String>('opened_by_user_id'),
              closedByUserId: r.readNullable<String>('closed_by_user_id'),
              status: r.read<String>('status'),
              openedAtMs: r.read<int>('opened_at_ms'),
              closedAtMs: r.readNullable<int>('closed_at_ms'),
              openingMinor: r.read<int>('opening_minor'),
              countedMinor: r.readNullable<int>('counted_minor'),
              notes: r.readNullable<String>('notes'),
              openingEventId: r.read<String>('created_event_id'),
              lastEventId: r.read<String>('last_event_id'),
              deliveryStatus: r.read<String>('delivery_status'),
              rejectionReason: r.readNullable<String>('rejection_reason'),
              closedIncomeMinor: _total(r, 'income_minor'),
              closedExpenseMinor: _total(r, 'expense_minor'),
              closedExpectedMinor: _total(r, 'expected_minor'),
              closedDifferenceMinor: _total(r, 'difference_minor'),
              movements: List.unmodifiable(
                items.map(
                  (m) => CashMovement(
                    id: m.read<String>('id'),
                    eventId: m.read<String>('created_event_id'),
                    direction: m.read<String>('direction'),
                    amountMinor: m.read<int>('amount_minor'),
                    sourceType:
                        m.readNullable<String>('sale_payment_id') != null
                        ? 'sale_payment'
                        : m.readNullable<String>('customer_payment_id') != null
                        ? 'customer_payment'
                        : m.readNullable<String>('sale_adjustment_id') != null
                        ? 'sale_adjustment'
                        : 'financial_entry',
                    sourceId:
                        (m.readNullable<String>('sale_payment_id') ??
                        m.readNullable<String>('customer_payment_id') ??
                        m.readNullable<String>('financial_entry_id') ??
                        m.readNullable<String>('sale_adjustment_id'))!,
                    deliveryStatus: m.read<String>('delivery_status'),
                    rejectionReason: m.readNullable<String>('rejection_reason'),
                  ),
                ),
              ),
            ),
          );
        }
        return sessions;
      });
  BigInt? _total(QueryRow r, String name) {
    final v = r.readNullable<String>(name);
    return v == null ? null : BigInt.parse(v);
  }
}
