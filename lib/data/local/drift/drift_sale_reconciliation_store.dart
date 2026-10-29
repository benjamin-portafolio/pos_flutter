import '../../../application/sync/payloads/sale_reconciliation_effect.dart';
import 'drift_customer_credit_store.dart';
import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../application/commands/ventas/sale_adjustment_command_contract.dart';
import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/models/sale_incident_details.dart';
import '../../../application/sync/payloads/operacion_venta_conciliada_payload.dart';
import '../../../application/sync/payloads/sale_adjustment_payload.dart';
import '../../../application/sync/payloads/sale_reconciliation_evidence.dart';
import '../../../application/sync/projections/sale_reconciliation_store.dart';
import 'app_database.dart' hide SaleReconciliationEffect;
import 'drift_sale_adjustment_store.dart';

class DriftSaleReconciliationStore implements SaleReconciliationStore {
  DriftSaleReconciliationStore(this.db);
  final AppDatabase db;
  @override
  Future<T> atomic<T>(Future<T> Function() action) => db.transaction(action);
  @override
  Future<SaleIncidentDetails?> incident(String id) async {
    final i = await (db.select(
      db.saleDeliveryIncidents,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (i == null) return null;
    final history = await DriftSaleAdjustmentStore(db).history(i.saleId);
    final official = history
        .where((e) => e.deliveryStatus == 'delivered')
        .toList();
    final confirmation = await DriftSaleAdjustmentStore(
      db,
    ).confirmation(i.saleId);
    if (confirmation == null) throw StateError('Falta confirmación histórica.');
    final loser = SaleAdjustmentPayload.fromJson(
      Map<String, Object?>.from(jsonDecode(i.preservedPayloadJson) as Map),
    );
    final attempts =
        await (db.select(db.events)..where(
              (t) =>
                  t.eventType.equals(OperacionVentaConciliadaPayload.eventType),
            ))
            .get();
    final recoveries = <String, SaleReconciliationEffect>{};
    for (final attempt in attempts) {
      final p = OperacionVentaConciliadaPayload.fromJson(
        Map<String, Object?>.from(jsonDecode(attempt.payload) as Map),
      );
      if (p.loserEventId == i.loserEventId) {
        for (final r in p.recoveryEffects) {
          recoveries[r.effectId] = r;
        }
      }
    }
    final declarations = [
      for (final e in attempts)
        if (OperacionVentaConciliadaPayload.fromJson(
              Map<String, Object?>.from(jsonDecode(e.payload) as Map),
            ).incidentId ==
            i.id)
          SaleAdjustmentDao.event(e),
    ];
    for (final r in await db.select(db.saleAdjustmentIntents).get()) {
      final e = SyncEvent.fromJson(
        Map<String, Object?>.from(jsonDecode(r.eventJson) as Map),
      );
      if (e.eventType == OperacionVentaConciliadaPayload.eventType &&
          OperacionVentaConciliadaPayload.fromJson(e.payload).incidentId ==
              i.id &&
          !declarations.any((x) => x.eventId == e.eventId)) {
        // Journal-only capture has not committed an event or business effects.
        declarations.add(e.copyWith(applicationStatus: 'pending'));
      }
    }
    final officialBase =
        official.lastOrNull?.eventId ??
        (confirmation.deliveryStatus == 'delivered'
            ? confirmation.eventId
            : null);
    final candidate = i.winnerEventId ?? officialBase;
    final candidateEvent = candidate == null
        ? null
        : await db.eventDao.obtenerEventoPorId(candidate);
    final winner = candidateEvent?.deliveryStatus == 'delivered'
        ? candidateEvent
        : null;
    final winnerId = winner?.eventId;
    return SaleIncidentDetails(
      id: i.id,
      saleId: i.saleId,
      reason: i.reason,
      loser: loser,
      winnerEventId: winnerId,
      winner: winner == null || winner.eventType == 'venta_confirmada'
          ? null
          : SaleAdjustmentPayload.fromJson(
              Map<String, Object?>.from(jsonDecode(winner.payload) as Map),
            ),
      officialBaseEventId: officialBase,
      blockedByEventId: i.blockedByEventId,
      officialRevision: official.length,
      evidence: SaleReconciliationEvidence.fromAdjustment(loser),
      recordedRecoveries: recoveries.values.toList(),
      attempts: declarations,
      resolutionEventId: i.resolutionEventId,
    );
  }

  @override
  Future<SyncEvent?> existing(String operationId, String eventId) async {
    if (await (db.select(
          db.saleAdjustments,
        )..where((a) => a.id.equals(operationId))).getSingleOrNull() !=
        null) {
      throw StateError('Identidad de documento ya utilizada.');
    }
    final rows =
        await (db.select(db.events)..where(
              (t) =>
                  t.eventId.equals(eventId) |
                  t.eventType.equals(OperacionVentaConciliadaPayload.eventType),
            ))
            .get();
    final matches = rows
        .where(
          (r) =>
              r.eventId == eventId ||
              OperacionVentaConciliadaPayload.fromJson(
                    Map<String, Object?>.from(jsonDecode(r.payload) as Map),
                  ).operationId ==
                  operationId,
        )
        .toList();
    if (matches.length > 1) throw StateError('Identidades incompatibles.');
    return matches.isEmpty ? null : _event(matches.single);
  }

  SyncEvent _event(EventRecord r) {
    final e = SaleAdjustmentDao.event(r);
    // events conserva segundos por compatibilidad; el contrato congela ms.
    return e.copyWith(
      createdAtLocal: DateTime.fromMillisecondsSinceEpoch(
        OperacionVentaConciliadaPayload.fromJson(e.payload).occurredAtMs,
        isUtc: true,
      ),
    );
  }

  @override
  Future<void> reserveIntention(SyncEvent e) => atomic(() async {
    final p = OperacionVentaConciliadaPayload.fromJson(e.payload);
    final old =
        await (db.select(db.saleAdjustmentIntents)..where(
              (t) =>
                  t.operationId.equals(p.operationId) |
                  t.eventId.equals(e.eventId),
            ))
            .get();
    if (old.isNotEmpty) {
      if (old.length != 1 ||
          !SaleAdjustmentCommandContract.sameIntention(
            SyncEvent.fromJson(
              Map<String, Object?>.from(
                jsonDecode(old.single.eventJson) as Map,
              ),
            ),
            e,
          )) {
        throw StateError('Identidad de intención ocupada.');
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
  Future<void> validate(
    OperacionVentaConciliadaPayload p, {
    required String deviceId,
  }) async {
    final i = await incident(p.incidentId);
    if (i == null || i.winnerEventId == null || i.officialBaseEventId == null) {
      throw StateError('Consulta el ganador oficial antes de conciliar.');
    }
    p.validateIncident(
      incident: i.id,
      sale: i.saleId,
      loser: i.loser.eventId,
      winner: i.winnerEventId!,
      officialBase: i.officialBaseEventId!,
      revision: i.officialRevision,
      evidence: i.evidence,
      alreadyConsumed: i.resolutionEventId != null,
    );
    final others =
        await (db.select(db.events)..where(
              (t) =>
                  t.eventType.equals(OperacionVentaConciliadaPayload.eventType),
            ))
            .get();
    if (others.any(
      (r) =>
          r.eventId != p.eventId &&
          !['conflict', 'rejected'].contains(r.deliveryStatus) &&
          OperacionVentaConciliadaPayload.fromJson(
                Map<String, Object?>.from(jsonDecode(r.payload) as Map),
              ).loserEventId ==
              p.loserEventId,
    )) {
      throw StateError('La incidencia ya tiene una conciliación pendiente.');
    }
    for (final r in i.recordedRecoveries) {
      if (!p.recoveryEffects.any(
        (e) => jsonEncode(e.toJson()) == jsonEncode(r.toJson()),
      )) {
        throw StateError(
          'Conserva la recuperación ya documentada con sus mismos IDs.',
        );
      }
    }
    final totals = <String, int>{};
    for (final effect in p.recoveryEffects) {
      if (effect.occurredAtMs < i.loser.occurredAtMs) {
        throw StateError(
          'La recuperación debe ser posterior a la operación local.',
        );
      }
      final key = '${effect.ledger}/${effect.targetId}';
      totals[key] = (totals[key] ?? 0) + effect.delta;
      final preserved = p.preservedEffects.where(
        (e) => e.ledger == effect.ledger && e.targetId == effect.targetId,
      );
      if (preserved.isEmpty ||
          preserved.fold(0, (n, e) => n + e.delta).sign == effect.delta.sign ||
          totals[key]!.abs() > preserved.fold(0, (n, e) => n + e.delta).abs()) {
        throw StateError('Recuperación sin diferencia justificable.');
      }
      if (effect.ledger == 'cash' && effect.cashSessionId != null) {
        final s = await (db.select(
          db.cashSessions,
        )..where((s) => s.id.equals(effect.cashSessionId!))).getSingleOrNull();
        if (s == null ||
            s.status != 'open' ||
            s.createdEventId != effect.openingEventId ||
            s.deviceId != deviceId ||
            effect.occurredAtMs < s.openedAtMs) {
          throw StateError('La recuperación exige caja actual abierta.');
        }
      }
    }
  }

  @override
  Future<void> apply(
    SyncEvent e,
    OperacionVentaConciliadaPayload p, {
    required bool official,
  }) => atomic(() async {
    final previous = await (db.select(
      db.saleReconciliationEffects,
    )..where((t) => t.eventId.equals(e.eventId))).get();
    final all = [...p.preservedEffects, ...p.recoveryEffects];
    for (final effect in all) {
      final existing = await (db.select(
        db.saleReconciliationEffects,
      )..where((t) => t.effectId.equals(effect.effectId))).getSingleOrNull();
      if (existing != null &&
          existing.payloadJson != jsonEncode(effect.toJson())) {
        throw StateError('Contenido de efecto incompatible.');
      }
      if (existing != null && existing.eventId != e.eventId) {
        final owner = await db.eventDao.obtenerEventoPorId(existing.eventId);
        if (owner == null ||
            !['conflict', 'rejected'].contains(owner.deliveryStatus) ||
            existing.payloadJson != jsonEncode(effect.toJson())) {
          throw StateError('Evidencia consumida por otra conciliación.');
        }
        await (db.update(
          db.saleReconciliationEffects,
        )..where((t) => t.effectId.equals(effect.effectId))).write(
          SaleReconciliationEffectsCompanion(eventId: Value(e.eventId)),
        );
      }
      final recovery = p.recoveryEffects.any(
        (r) => r.effectId == effect.effectId,
      );
      final stock = await (db.select(
        db.inventoryMovements,
      )..where((t) => t.movementId.equals(effect.effectId))).getSingleOrNull();
      final cash = await (db.select(
        db.cashMovements,
      )..where((t) => t.id.equals(effect.effectId))).getSingleOrNull();
      if (stock != null &&
          (stock.eventId != p.loserEventId ||
              stock.inventoryItemId != effect.targetId ||
              stock.quantityDeltaAtomic != effect.delta)) {
        throw StateError('Identidad física incompatible.');
      }
      if (cash != null &&
          (cash.createdEventId != p.loserEventId ||
              cash.sessionId != effect.cashSessionId ||
              (cash.direction == 'in' ? cash.amountMinor : -cash.amountMinor) !=
                  effect.delta)) {
        throw StateError('Evidencia de caja incompatible.');
      }
      final physical =
          stock != null ||
          cash != null ||
          (effect.ledger == 'credit' &&
              await (db.select(db.saleAdjustments)
                        ..where((t) => t.eventId.equals(p.loserEventId)))
                      .getSingleOrNull() !=
                  null);
      final apply =
          (official || recovery) && !(existing?.appliedLocally ?? physical);
      if (apply && effect.ledger == 'stock') {
        final b = await (db.select(
          db.inventoryBalances,
        )..where((t) => t.inventoryItemId.equals(effect.targetId))).getSingle();
        for (final value in [
          BigInt.from(b.quantityOnHandAtomic) + BigInt.from(effect.delta),
          BigInt.from(b.quantityAvailableAtomic) + BigInt.from(effect.delta),
        ]) {
          if (value.abs() > BigInt.from(9007199254740991)) {
            throw StateError('Saldo fuera de rango.');
          }
        }
        await (db.update(
          db.inventoryBalances,
        )..where((t) => t.inventoryItemId.equals(effect.targetId))).write(
          InventoryBalancesCompanion(
            quantityOnHandAtomic: Value(b.quantityOnHandAtomic + effect.delta),
            quantityAvailableAtomic: Value(
              b.quantityAvailableAtomic + effect.delta,
            ),
            lastEventId: Value(e.eventId),
            lastServerSequence: Value(e.serverSequence),
          ),
        );
      }
      final applied =
          (existing?.appliedLocally ?? false) ||
          physical ||
          official ||
          recovery;
      if (existing == null) {
        await db
            .into(db.saleReconciliationEffects)
            .insert(
              SaleReconciliationEffectsCompanion.insert(
                effectId: effect.effectId,
                eventId: e.eventId,
                ledger: effect.ledger,
                isRecovery: recovery,
                targetId: effect.targetId,
                delta: effect.delta,
                cashSessionId: Value(effect.cashSessionId),
                payloadJson: jsonEncode(effect.toJson()),
                appliedLocally: applied,
              ),
            );
      } else if (applied != existing.appliedLocally) {
        await (db.update(
          db.saleReconciliationEffects,
        )..where((t) => t.effectId.equals(effect.effectId))).write(
          SaleReconciliationEffectsCompanion(appliedLocally: Value(applied)),
        );
      }
    }
    if (official) {
      await (db.update(
        db.saleDeliveryIncidents,
      )..where((t) => t.loserEventId.equals(p.loserEventId))).write(
        SaleDeliveryIncidentsCompanion(
          resolutionEventId: Value(e.eventId),
          lastEventId: Value(e.eventId),
          lastServerSequence: Value(e.serverSequence),
        ),
      );
    }
    if (official) {
      for (final id
          in all
              .where((e) => e.ledger == 'credit')
              .map((e) => e.targetId)
              .toSet()) {
        await DriftCustomerCreditStore(db).rebuild(id);
      }
    }
    // previous consultado dentro del límite transaccional para detectar reaplicación.
    if (previous.length > all.length) {
      throw StateError('Libro de conciliación incompatible.');
    }
  });
  @override
  Future<void> acknowledge(SyncEvent e) => apply(
    e,
    OperacionVentaConciliadaPayload.fromJson(e.payload),
    official: true,
  );
}
