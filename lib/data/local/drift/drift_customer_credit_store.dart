import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/payloads/abono_cliente_registrado_payload.dart';
import '../../../application/sync/projections/customer_credit_store.dart';
import '../../../domain/creditos/account_entry.dart';
import '../../../domain/creditos/customer_account.dart';
import 'app_database.dart';

class DriftCustomerCreditStore implements CustomerCreditStore {
  DriftCustomerCreditStore(this.db);
  final AppDatabase db;
  @override
  Future<T> atomic<T>(Future<T> Function() action) => db.transaction(action);
  @override
  Future<SyncEvent?> paymentEvent(String id) async {
    final row = await (db.select(
      db.customerPayments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final e = await (db.select(
      db.events,
    )..where((t) => t.eventId.equals(row.createdEventId!))).getSingle();
    return SyncEvent(
      eventId: e.eventId,
      aggregateType: e.aggregateType,
      aggregateId: e.aggregateId,
      eventType: e.eventType,
      deviceId: e.deviceId,
      userId: e.userId,
      createdAtLocal: e.createdAtLocal,
      payload: Map<String, Object?>.from(jsonDecode(e.payload) as Map),
    );
  }

  @override
  Future<void> applyPayment(SyncEvent event, AbonoClienteRegistradoPayload p) =>
      atomic(() async {
        final existing = await (db.select(
          db.customerPayments,
        )..where((t) => t.id.equals(event.aggregateId))).getSingleOrNull();
        if (existing != null) {
          if (existing.createdEventId != event.eventId) {
            throw StateError('Identidad de abono ocupada.');
          }
          return;
        }
        final cliente = await db.clienteDao.findById(p.clienteId);
        if (cliente == null || cliente.createdEventId != p.clienteEventId) {
          throw StateError('Falta el cliente del abono.');
        }
        await db
            .into(db.customerPayments)
            .insert(
              CustomerPaymentsCompanion.insert(
                id: event.aggregateId,
                clienteId: p.clienteId,
                amountMinor: p.amountMinor,
                method: p.method,
                reference: Value(p.reference),
                occurredAtMs: p.occurredAtMs,
                createdEventId: Value(event.eventId),
                lastEventId: Value(event.eventId),
                lastServerSequence: Value(event.serverSequence),
              ),
            );
        await rebuild(p.clienteId);
      });
  Future<void> rebuild(String clienteId) async {
    final credits = await (db.select(
      db.creditSales,
    )..where((t) => t.clienteId.equals(clienteId))).get();
    final payments = await (db.select(
      db.customerPayments,
    )..where((t) => t.clienteId.equals(clienteId))).get();
    final activeIds = (await db.select(db.saleAdjustments).get())
        .where((a) => a.commercialActive)
        .map((a) => a.id)
        .toSet();
    final reductions = (await db.select(db.saleCreditReductions).get()).where(
      (r) => activeIds.contains(r.operationId),
    );
    int net(CreditSaleRow c) {
      final amount =
          BigInt.from(c.amountMinor) -
          reductions
              .where((r) => r.creditId == c.id)
              .fold(BigInt.zero, (sum, r) => sum + BigInt.from(r.amountMinor));
      if (amount.isNegative) throw StateError('Reducción excesiva.');
      return amount.toInt();
    }

    final notes = await db
        .customSelect(
          "SELECT r.*,e.delivery_status FROM sale_reconciliation_effects r JOIN events e ON e.event_id=r.event_id WHERE r.ledger='credit' AND r.target_id=? AND e.delivery_status='delivered'",
          variables: [Variable(clienteId)],
        )
        .get();
    final account = CustomerAccount([
      for (final r in notes)
        AccountEntry(
          id: r.read<String>('effect_id'),
          eventId: r.read<String>('event_id'),
          amountMinor: r.read<int>('delta').abs(),
          occurredAtMs:
              (jsonDecode(r.read<String>('payload_json'))
                      as Map)['occurred_at_ms']
                  as int,
          isPayment: r.read<int>('delta') > 0,
          deliveryStatus: 'delivered',
          isReconciliation: true,
        ),
      for (final c in credits)
        AccountEntry(
          id: c.id,
          eventId: c.createdEventId!,
          amountMinor: net(c),
          occurredAtMs: c.occurredAtMs,
          isPayment: false,
          deliveryStatus: '',
          saleId: c.saleId,
        ),
      for (final p in payments)
        AccountEntry(
          id: p.id,
          eventId: p.createdEventId!,
          amountMinor: p.amountMinor,
          occurredAtMs: p.occurredAtMs,
          isPayment: true,
          deliveryStatus: '',
        ),
    ]);
    if (credits.isNotEmpty) {
      await (db.delete(
        db.creditAllocations,
      )..where((t) => t.creditId.isIn(credits.map((c) => c.id)))).go();
    }
    await db.batch(
      (b) => b.insertAll(db.creditAllocations, [
        for (final a in account.allocations)
          if (payments.any((p) => p.id == a.paymentId) &&
              credits.any((c) => c.id == a.creditId))
            CreditAllocationsCompanion.insert(
              paymentId: a.paymentId,
              creditId: a.creditId,
              amountMinor: a.amountMinor,
            ),
      ]),
    );
  }

  @override
  Future<void> acknowledge(String eventId, int serverSequence) async {
    await (db.update(
      db.customerPayments,
    )..where((t) => t.createdEventId.equals(eventId))).write(
      CustomerPaymentsCompanion(lastServerSequence: Value(serverSequence)),
    );
    await (db.update(db.creditSales)
          ..where((t) => t.createdEventId.equals(eventId)))
        .write(CreditSalesCompanion(lastServerSequence: Value(serverSequence)));
  }
}
