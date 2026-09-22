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
    final account = CustomerAccount([
      for (final c in credits)
        AccountEntry(
          id: c.id,
          eventId: c.createdEventId!,
          amountMinor: c.amountMinor,
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
