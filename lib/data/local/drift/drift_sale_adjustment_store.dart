import '../../../application/sync/payloads/sale_reconciliation_evidence.dart';
import 'package:uuid/uuid.dart';
import '../../../application/sync/models/sale_adjustment_delivery_state.dart';
import '../../../application/sync/payloads/venta_anulada_payload.dart';
import '../../../application/sync/payloads/devolucion_venta_registrada_payload.dart';
import 'drift_customer_credit_store.dart';
import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../application/commands/ventas/sale_adjustment_command_contract.dart';
import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/payloads/sale_adjustment_payload.dart';
import '../../../application/sync/payloads/sale_adjustment_rules.dart';
import '../../../application/sync/payloads/venta_confirmada_payload.dart';
import '../../../application/sync/projections/sale_adjustment_store.dart';
import 'app_database.dart';
import '../../../domain/ventas/sale_status.dart';

class DriftSaleAdjustmentStore implements SaleAdjustmentStore {
  DriftSaleAdjustmentStore(this.db) : dao = db.saleAdjustmentDao;
  final AppDatabase db;
  final SaleAdjustmentDao dao;

  /// Incluye todas las operaciones no oficiales una sola vez; los libros físicos
  /// permanecen intactos. Las cuentas FIFO usan la rama comercial activa.
  @override
  Future<SaleAdjustmentDeliveryState> readDeliveryState() => atomic(() async {
    final reconciliationEvents = {
      for (final e in await db.select(db.events).get())
        e.eventId: e.aggregateId,
    };
    final eventRows = {
      for (final e in await db.select(db.events).get())
        e.eventId: e.deliveryStatus,
    };
    final reconciliations = await db.select(db.saleReconciliationEffects).get();
    final recognized = reconciliations
        .where(
          (r) => ['delivered', 'not_required'].contains(eventRows[r.eventId]),
        )
        .map((r) => r.effectId)
        .toSet();
    final stockDelta = <String, BigInt>{},
        cashDelta = <String, BigInt>{},
        creditDelta = <String, BigInt>{};
    for (final a in await db.select(db.saleAdjustments).get()) {
      final e = await db.eventDao.obtenerEventoPorId(a.eventId);
      if (e == null ||
          ['delivered', 'not_required'].contains(e.deliveryStatus)) {
        continue;
      }
      final p = SaleAdjustmentPayload.fromJson(
        Map<String, Object?>.from(jsonDecode(a.payloadJson) as Map),
      );
      if (p.settlement.method == 'credit' &&
          !recognized.contains(
            SaleReconciliationEvidence.documentaryEffectId(
              p.operationId,
              'credit',
            ),
          )) {
        creditDelta.update(
          p.saleId,
          (v) => v + BigInt.from(p.totalMinor),
          ifAbsent: () => BigInt.from(p.totalMinor),
        );
      }
    }
    // El oficial tampoco incorpora otros movimientos pendientes de la cadena
    // (por ejemplo la confirmación origen). Cada fila del libro cuenta una vez.
    final eventStatus = {
      for (final e in await db.select(db.events).get())
        e.eventId: e.deliveryStatus,
    };
    for (final m in await db.select(db.inventoryMovements).get()) {
      if (recognized.contains(m.movementId) ||
          ['delivered', 'not_required'].contains(eventStatus[m.eventId])) {
        continue;
      }
      stockDelta.update(
        m.inventoryItemId,
        (v) => v + BigInt.from(m.quantityDeltaAtomic),
        ifAbsent: () => BigInt.from(m.quantityDeltaAtomic),
      );
    }
    for (final m in await db.select(db.cashMovements).get()) {
      if (recognized.contains(m.id) ||
          [
            'delivered',
            'not_required',
          ].contains(eventStatus[m.createdEventId])) {
        continue;
      }
      final amount =
          BigInt.from(m.amountMinor) *
          (m.direction == 'in' ? BigInt.one : -BigInt.one);
      cashDelta.update(m.sessionId, (v) => v + amount, ifAbsent: () => amount);
    }
    for (final session in await db.select(db.cashSessions).get()) {
      if ([
        'delivered',
        'not_required',
      ].contains(eventStatus[session.createdEventId])) {
        continue;
      }
      cashDelta.update(
        session.id,
        (v) => v + BigInt.from(session.openingMinor),
        ifAbsent: () => BigInt.from(session.openingMinor),
      );
    }
    final physicalCashIds = (await db.select(db.cashMovements).get())
        .map((m) => m.id)
        .toSet();
    for (final r in reconciliations.where(
      (r) => r.appliedLocally && !recognized.contains(r.effectId),
    )) {
      if (r.ledger == 'stock' &&
          !(await db.select(db.inventoryMovements).get()).any(
            (m) => m.movementId == r.effectId,
          )) {
        stockDelta.update(
          r.targetId,
          (v) => v + BigInt.from(r.delta),
          ifAbsent: () => BigInt.from(r.delta),
        );
      }
      if (r.ledger == 'cash' &&
          r.cashSessionId != null &&
          !physicalCashIds.contains(r.effectId)) {
        cashDelta.update(
          r.cashSessionId!,
          (v) => v + BigInt.from(r.delta),
          ifAbsent: () => BigInt.from(r.delta),
        );
      }
    }
    final inventory =
        <
          String,
          ({BigInt recorded, BigInt official, BigInt localDifference})
        >{};
    for (final b in await db.select(db.inventoryBalances).get()) {
      final recorded = BigInt.from(b.quantityOnHandAtomic),
          difference = stockDelta[b.inventoryItemId] ?? BigInt.zero;
      inventory[b.inventoryItemId] = (
        recorded: recorded,
        official: recorded - difference,
        localDifference: difference,
      );
    }
    final cash =
        <
          String,
          ({BigInt recorded, BigInt official, BigInt localDifference})
        >{};
    for (final session in await db.select(db.cashSessions).get()) {
      final movements = await (db.select(
        db.cashMovements,
      )..where((t) => t.sessionId.equals(session.id))).get();
      final recorded = movements.fold(
        BigInt.from(session.openingMinor),
        (s, m) =>
            s +
            (m.direction == 'in'
                ? BigInt.from(m.amountMinor)
                : -BigInt.from(m.amountMinor)),
      );
      final regularized = reconciliations
          .where(
            (r) =>
                r.ledger == 'cash' &&
                r.cashSessionId == session.id &&
                r.appliedLocally &&
                !physicalCashIds.contains(r.effectId),
          )
          .fold(BigInt.zero, (n, r) => n + BigInt.from(r.delta));
      final totalRecorded = recorded + regularized;
      final difference = cashDelta[session.id] ?? BigInt.zero;
      cash[session.id] = (
        recorded: totalRecorded,
        official: totalRecorded - difference,
        localDifference: difference,
      );
    }
    final credit =
        <
          String,
          ({BigInt recorded, BigInt official, BigInt localDifference})
        >{};
    for (final c in await db.select(db.creditSales).get()) {
      final rows = await (db.select(
        db.saleCreditReductions,
      )..where((t) => t.creditId.equals(c.id))).get();
      final extra = reconciliations
          .where(
            (r) =>
                r.ledger == 'credit' &&
                r.appliedLocally &&
                reconciliationEvents[r.eventId] == c.saleId &&
                !rows.any(
                  (x) =>
                      SaleReconciliationEvidence.documentaryEffectId(
                        x.operationId,
                        'credit',
                      ) ==
                      r.effectId,
                ),
          )
          .toList();
      for (final r in extra.where((r) => !recognized.contains(r.effectId))) {
        creditDelta.update(
          c.saleId,
          (n) => n + BigInt.from(r.delta),
          ifAbsent: () => BigInt.from(r.delta),
        );
      }
      final recorded =
              extra.fold(BigInt.zero, (n, r) => n + BigInt.from(r.delta)) +
              rows.fold(BigInt.zero, (s, r) => s + BigInt.from(r.amountMinor)),
          difference = creditDelta[c.saleId] ?? BigInt.zero;
      credit[c.saleId] = (
        recorded: recorded,
        official: recorded - difference,
        localDifference: difference,
      );
    }
    return SaleAdjustmentDeliveryState(
      inventory: Map.unmodifiable(inventory),
      cash: Map.unmodifiable(cash),
      creditReductions: Map.unmodifiable(credit),
      incidentEventIds: List.unmodifiable(
        (await (db.select(
          db.saleDeliveryIncidents,
        )..where((t) => t.resolutionEventId.isNull())).get()).map(
          (i) => i.loserEventId,
        ),
      ),
    );
  });
  @override
  Future<T> atomic<T>(Future<T> Function() action) => db.transaction(action);
  @override
  Future<SyncEvent?> confirmation(String saleId) async {
    final sale = await db.saleDao.findById(saleId);
    if (sale?.status != SaleStatus.confirmada) return null;
    final row = await db.eventDao.obtenerEventoPorId(sale!.createdEventId!);
    if (row == null ||
        row.eventType != VentaConfirmadaPayload.eventType ||
        row.applicationStatus != 'applied') {
      return null;
    }
    return SaleAdjustmentDao.event(row);
  }

  @override
  Future<bool> hasIncident(String saleId) async =>
      (await (db.select(db.saleDeliveryIncidents)..where(
                (t) => t.saleId.equals(saleId) & t.resolutionEventId.isNull(),
              ))
              .get())
          .isNotEmpty;
  Future<void> preserveIncident(
    String eventId,
    String reason, {
    String? winnerEventId,
    String? blockedByEventId,
  }) => atomic(() async {
    final row = await db.eventDao.obtenerEventoPorId(eventId);
    if (row == null ||
        ![
          VentaAnuladaPayload.eventType,
          DevolucionVentaRegistradaPayload.eventType,
        ].contains(row.eventType)) {
      return;
    }
    final p = SaleAdjustmentPayload.fromJson(
      Map<String, Object?>.from(jsonDecode(row.payload) as Map),
    );
    if (blockedByEventId == null) {
      for (final id in p.dependencyEventIds) {
        final dependency = await db.eventDao.obtenerEventoPorId(id);
        if (dependency != null &&
            [
              'conflict',
              'rejected',
              'not_required',
            ].contains(dependency.deliveryStatus)) {
          blockedByEventId = id;
          break;
        }
      }
    }
    final existing = await (db.select(
      db.saleDeliveryIncidents,
    )..where((t) => t.loserEventId.equals(eventId))).getSingleOrNull();
    if (existing == null) {
      await db
          .into(db.saleDeliveryIncidents)
          .insert(
            SaleDeliveryIncidentsCompanion.insert(
              id: eventId,
              saleId: p.saleId,
              loserEventId: eventId,
              reason: reason,
              preservedPayloadJson: row.payload,
              winnerEventId: Value(winnerEventId),
              blockedByEventId: Value(blockedByEventId),
              createdEventId: Value(eventId),
              lastEventId: Value(eventId),
            ),
          );
    } else if (winnerEventId != null) {
      await (db.update(
        db.saleDeliveryIncidents,
      )..where((t) => t.id.equals(existing.id))).write(
        SaleDeliveryIncidentsCompanion(winnerEventId: Value(winnerEventId)),
      );
    }
    await (db.update(db.saleAdjustments)
          ..where((t) => t.eventId.equals(eventId)))
        .write(const SaleAdjustmentsCompanion(commercialActive: Value(false)));
    if (p.settlement.method == 'credit' && p.settlement.clienteId != null) {
      await DriftCustomerCreditStore(db).rebuild(p.settlement.clienteId!);
    }
  });
  @override
  Future<void> prepareOfficial(SyncEvent event) => atomic(() async {
    final p = SaleAdjustmentPayload.fromJson(event.payload);
    final rows = await dao.forSale(p.saleId);
    for (final d in rows) {
      if (d.eventId == event.eventId) continue;
      final local = await db.eventDao.obtenerEventoPorId(d.eventId);
      if (local != null &&
          local.deliveryStatus != 'delivered' &&
          local.deliveryStatus != 'not_required' &&
          d.revision >= p.expectedRevision + 1) {
        const reason =
            'Operación física conservada: otra operación oficial ocupó su revisión.';
        await (db.update(
          db.events,
        )..where((t) => t.eventId.equals(d.eventId))).write(
          const EventsCompanion(
            deliveryStatus: Value('conflict'),
            rejectionReason: Value(reason),
          ),
        );
        await preserveIncident(d.eventId, reason, winnerEventId: event.eventId);
      }
    }
  });
  @override
  Future<void> acknowledge(String eventId, int sequence) => atomic(() async {
    await (db.update(db.saleAdjustments)
          ..where((t) => t.eventId.equals(eventId)))
        .write(SaleAdjustmentsCompanion(lastServerSequence: Value(sequence)));
    await (db.update(db.inventoryMovements)
          ..where((t) => t.eventId.equals(eventId)))
        .write(InventoryMovementsCompanion(serverSequence: Value(sequence)));
    await (db.update(db.inventoryBalances)
          ..where((t) => t.lastEventId.equals(eventId)))
        .write(InventoryBalancesCompanion(lastServerSequence: Value(sequence)));
    await (db.update(db.cashMovements)
          ..where((t) => t.createdEventId.equals(eventId)))
        .write(CashMovementsCompanion(lastServerSequence: Value(sequence)));
  });
  @override
  Future<List<SyncEvent>> history(String saleId) async => [
    for (final a in (await dao.forSale(
      saleId,
    )).where((a) => a.commercialActive))
      SaleAdjustmentDao.event(
        (await db.eventDao.obtenerEventoPorId(a.eventId))!,
      ),
  ];
  @override
  Future<SyncEvent?> existing(String operationId, String eventId) async {
    final rows =
        await (db.select(db.saleAdjustments)..where(
              (t) => t.id.equals(operationId) | t.eventId.equals(eventId),
            ))
            .get();
    if (rows.length > 1) {
      throw StateError('Identidades de ajuste incompatibles.');
    }
    final direct = await db.eventDao.obtenerEventoPorId(eventId);
    if (rows.isEmpty) {
      if (direct != null) throw StateError('Identidad de evento ocupada.');
      return null;
    }
    return SaleAdjustmentDao.event(
      (await db.eventDao.obtenerEventoPorId(rows.single.eventId))!,
    );
  }

  @override
  Future<void> reserveIntention(SyncEvent e) => atomic(() async {
    final p = SaleAdjustmentPayload.fromJson(e.payload);
    final rows =
        await (db.select(db.saleAdjustmentIntents)..where(
              (t) =>
                  t.operationId.equals(p.operationId) |
                  t.eventId.equals(e.eventId),
            ))
            .get();
    if (rows.isNotEmpty) {
      if (rows.length != 1 ||
          !SaleAdjustmentCommandContract.sameIntention(
            SyncEvent.fromJson(
              Map<String, Object?>.from(
                jsonDecode(rows.single.eventJson) as Map,
              ),
            ),
            e,
          )) {
        throw StateError('La identidad ya pertenece a otra intención.');
      }
      return;
    }
    await db
        .into(db.saleAdjustmentIntents)
        .insert(
          SaleAdjustmentIntentsCompanion.insert(
            operationId: p.operationId,
            eventId: e.eventId,
            eventJson: jsonEncode({
              ...e.toPushJson(),
              'application_status': e.applicationStatus,
              'delivery_status': e.deliveryStatus,
            }),
          ),
        );
  });
  @override
  Future<List<SyncEvent>> recoverableIntentions(String saleId) async {
    final rows = await db.select(db.saleAdjustmentIntents).get();
    final result = <SyncEvent>[];
    for (final r in rows) {
      final e = SyncEvent.fromJson(
        Map<String, Object?>.from(jsonDecode(r.eventJson) as Map),
      );
      if (e.aggregateId == saleId &&
          [
            VentaAnuladaPayload.eventType,
            DevolucionVentaRegistradaPayload.eventType,
          ].contains(e.eventType) &&
          await db.eventDao.obtenerEventoPorId(e.eventId) == null) {
        result.add(e);
      }
    }
    return result;
  }

  @override
  Future<SyncEvent?> recoverIntention(String operationId) async {
    final r = await (db.select(
      db.saleAdjustmentIntents,
    )..where((t) => t.operationId.equals(operationId))).getSingleOrNull();
    return r == null
        ? null
        : SyncEvent.fromJson(
            Map<String, Object?>.from(jsonDecode(r.eventJson) as Map),
          );
  }

  @override
  Future<void> persistDocument(SyncEvent e, SaleAdjustmentPayload p) => atomic(
    () async {
      final prior =
          await (db.select(db.saleAdjustments)..where(
                (t) => t.id.equals(p.operationId) | t.eventId.equals(e.eventId),
              ))
              .get();
      if (prior.isNotEmpty) {
        final stored = SaleAdjustmentDao.event(
          (await db.eventDao.obtenerEventoPorId(prior.single.eventId))!,
        );
        if (!SaleAdjustmentCommandContract.sameIntention(stored, e)) {
          throw StateError('Identidad ocupada.');
        }
        return;
      }
      final source = await confirmation(p.saleId);
      if (source == null) throw StateError('Se requiere una venta confirmada.');
      SaleAdjustmentRules.validate(
        p,
        VentaConfirmadaPayload.fromJson(source.payload),
        confirmationEventId: source.eventId,
        saleId: source.aggregateId,
        history: (await history(
          p.saleId,
        )).map((e) => SaleAdjustmentPayload.fromJson(e.payload)).toList(),
      );
      await dao.insert(e, p);
      if (e.deliveryStatus == 'delivered' && e.serverSequence != null) {
        final refs = SaleAdjustmentRules.refs(
          p,
          VentaConfirmadaPayload.fromJson(source.payload),
        );
        for (final r in refs) {
          await db
              .into(db.eventRefs)
              .insert(
                EventRefsCompanion.insert(
                  eventRefId: const Uuid().v4(),
                  eventId: e.eventId,
                  refType: r.refType,
                  refId: r.refId,
                  relationship: r.relationship,
                  source: 'server',
                  serverSequence: Value(e.serverSequence),
                ),
              );
        }
      }
    },
  );
  @override
  Future<void> applyEffects(SyncEvent e, SaleAdjustmentPayload p) async {
    for (final line in p.lines) {
      for (final m in line.stock) {
        final original = await (db.select(
          db.inventoryMovements,
        )..where((t) => t.movementId.equals(m.originalMovementId))).getSingle();
        if (original.saleItemId != line.saleItemId ||
            original.inventoryItemId != m.inventoryItemId ||
            original.eventId != p.confirmationEventId ||
            original.movementType != 'sale_consumption') {
          throw StateError('Consumo histórico incompatible.');
        }
        final balance =
            await (db.select(db.inventoryBalances)
                  ..where((t) => t.inventoryItemId.equals(m.inventoryItemId)))
                .getSingle();
        int next(int value) {
          final result = BigInt.from(value) + BigInt.from(m.quantityAtomic);
          if (result.abs() > BigInt.from(9007199254740991)) {
            throw StateError('Saldo fuera de rango.');
          }
          return result.toInt();
        }

        await db
            .into(db.inventoryMovements)
            .insert(
              InventoryMovementsCompanion.insert(
                movementId: m.movementId,
                inventoryItemId: m.inventoryItemId,
                saleItemId: Value(line.saleItemId),
                eventId: e.eventId,
                saleAdjustmentId: Value(p.operationId),
                reversalOfMovementId: Value(m.originalMovementId),
                movementType: p.kind == 'void'
                    ? 'sale_void_restock'
                    : 'sale_return_restock',
                quantityDeltaAtomic: m.quantityAtomic,
                createdAtLocal: e.createdAtLocal,
                serverSequence: Value(e.serverSequence),
              ),
            );
        await (db.update(
          db.inventoryBalances,
        )..where((t) => t.inventoryItemId.equals(m.inventoryItemId))).write(
          InventoryBalancesCompanion(
            quantityOnHandAtomic: Value(next(balance.quantityOnHandAtomic)),
            quantityAvailableAtomic: Value(
              next(balance.quantityAvailableAtomic),
            ),
            version: Value(balance.version + 1),
            lastEventId: Value(e.eventId),
            lastServerSequence: Value(e.serverSequence),
          ),
        );
      }
    }
    final binding = p.settlement.cash;
    if (binding != null) {
      final session = await (db.select(
        db.cashSessions,
      )..where((t) => t.id.equals(binding.sessionId))).getSingle();
      if ((session.status != 'open' && e.deliveryStatus != 'delivered') ||
          session.deviceId != e.deviceId ||
          session.createdEventId != binding.openingEventId) {
        throw StateError('Caja actual incompatible.');
      }
      await db
          .into(db.cashMovements)
          .insert(
            CashMovementsCompanion.insert(
              id: binding.movementId,
              sessionId: binding.sessionId,
              direction: 'out',
              amountMinor: p.totalMinor,
              saleAdjustmentId: Value(p.operationId),
              createdEventId: Value(e.eventId),
              lastEventId: Value(e.eventId),
              lastServerSequence: Value(e.serverSequence),
            ),
          );
    }
    if (p.settlement.method == 'credit' && p.totalMinor > 0) {
      final credit = await (db.select(
        db.creditSales,
      )..where((t) => t.saleId.equals(p.saleId))).getSingle();
      if (credit.clienteId != p.settlement.clienteId ||
          credit.createdEventId != p.confirmationEventId) {
        throw StateError('Cargo histórico incompatible.');
      }
      final activeIds = (await db.select(db.saleAdjustments).get())
          .where((a) => a.commercialActive)
          .map((a) => a.id)
          .toSet();
      final reductions = await (db.select(
        db.saleCreditReductions,
      )..where((t) => t.creditId.equals(credit.id))).get();
      final total = reductions.fold(
        BigInt.from(p.totalMinor),
        (sum, r) =>
            sum +
            (activeIds.contains(r.operationId)
                ? BigInt.from(r.amountMinor)
                : BigInt.zero),
      );
      if (total > BigInt.from(credit.amountMinor)) {
        throw StateError('Reducción excesiva.');
      }
      await db
          .into(db.saleCreditReductions)
          .insert(
            SaleCreditReductionsCompanion.insert(
              operationId: p.operationId,
              creditId: credit.id,
              amountMinor: p.totalMinor,
            ),
          );
      await DriftCustomerCreditStore(db).rebuild(credit.clienteId);
    }
  }
}
