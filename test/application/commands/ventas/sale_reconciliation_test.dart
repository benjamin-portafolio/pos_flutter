import 'package:pos_flutter/application/sync/revalidation/sale_adjustment_pending_event_validator.dart';
import 'package:pos_flutter/data/repositories/cliente_resumen_repository_impl.dart';
import 'package:pos_flutter/data/repositories/transfer_summary_repository_impl.dart';
import 'package:pos_flutter/data/repositories/customer_account_repository_impl.dart';
import 'package:pos_flutter/application/commands/caja/caja_command_service.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/prepare_sale_adjustment.dart';
import 'package:pos_flutter/application/commands/ventas/sale_reconciliation_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/conciliar_operacion_venta_command.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/sale_adjustment_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/sale_reconciliation_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/operacion_venta_conciliada_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sale_reconciliation_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import '../../../support/sale_adjustment_harness.dart';

class ReconciliationHarness {
  ReconciliationHarness(this.h);
  final SaleAdjustmentHarness h;
  late final store = DriftSaleReconciliationStore(h.db);
  late final handler = SaleReconciliationEventHandler(
    store: store,
    config: h.config,
    isolatedSyncHarness: true,
  );
  late final events = DriftLocalEventStore(
    db: h.db,
    eventDao: h.db.eventDao,
    eventRefDao: h.db.eventRefDao,
    appConfigController: h.config,
    eventProcessor: EventProcessor(
      handlers: {OperacionVentaConciliadaPayload.eventType: handler.apply},
    ),
  );
  late final commands = SaleReconciliationCommandService(
    store: store,
    events: events,
    config: h.config,
    context: h.context,
    isolatedSyncHarness: true,
  );
  late final persistence = DriftSyncPersistence(
    db: h.db,
    eventDao: h.db.eventDao,
    eventRefDao: h.db.eventRefDao,
    syncCheckpointDao: h.db.syncCheckpointDao,
  );
  late String incidentId, saleId, resourceId;
  static Future<ReconciliationHarness> create({
    String fixtureName = 'cash_disabled_no_drawer',
  }) async {
    final h = await SaleAdjustmentHarness.create();
    final f = adjustmentFixtures().firstWhere((f) => f['name'] == fixtureName);
    await h.seed(f);
    await h.db
        .update(h.db.events)
        .write(
          const EventsCompanion(
            deliveryStatus: Value('delivered'),
            serverSequence: Value(1),
          ),
        );
    h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
    final adjustmentHandler = SaleAdjustmentEventHandler(
      store: h.store,
      cash: h.cashStore,
      config: h.config,
      isolatedSyncHarness: true,
    );
    final service = SaleAdjustmentCommandService(
      store: h.store,
      events: h.events(adjustmentHandler.apply),
      config: h.config,
      context: h.context,
      isolatedSyncHarness: true,
    );
    final prepare = PrepareSaleAdjustment(service, h.cashStore);
    final saleId = object(f['payload'])['sale_id'] as String;
    final source = object((object(f['original'])['lines'] as List).first);
    final id = source['sale_item_id'] as String;
    final winner = await prepare(
      saleId: saleId,
      expectedRevision: 0,
      voidSale: false,
      reason: 'Ganador',
      action: 'refund_completed',
      reference: object(f['original'])['payment_method'] == 'transfer'
          ? 'REF'
          : null,
      selections: {id: (quantity: 1, destination: 'restock')},
    );
    final loser = await prepare(
      saleId: saleId,
      expectedRevision: 0,
      voidSale: true,
      reason: 'Local ya realizado',
      action: 'refund_completed',
      reference: object(f['original'])['payment_method'] == 'transfer'
          ? 'REF'
          : null,
    );
    await h.execute(loser.toJson(), commands: service);
    final remote = h
        .prepare(f, payload: winner)
        .event
        .copyWith(deliveryStatus: 'delivered', serverSequence: 2);
    await DriftSyncedEventStore(db: h.db).applySyncedEvents(
      [remote],
      applyEvent: adjustmentHandler.apply,
      acknowledgeEcho: (_) async {},
    );
    return ReconciliationHarness(h)
      ..incidentId = loser.eventId
      ..saleId = saleId
      ..resourceId =
          object((source['consumptions'] as List).first)['inventory_item_id']
              as String;
  }

  Future<OperacionVentaConciliadaPayload> payload({
    bool recoverStock = false,
  }) async {
    final i = (await store.incident(incidentId))!;
    final now = DateTime.now().toUtc();
    final stock = i.evidence.firstWhere((e) => e.ledger == 'stock');
    return OperacionVentaConciliadaPayload.fromJson({
      'schema_version': 1,
      'operation_id': const Uuid().v4(),
      'event_id': const Uuid().v4(),
      'incident_id': i.id,
      'sale_id': i.saleId,
      'loser_event_id': i.loser.eventId,
      'winner_event_id': i.winnerEventId,
      'official_base_event_id': i.officialBaseEventId,
      'expected_revision': i.officialRevision,
      'occurred_at_ms': now.millisecondsSinceEpoch,
      'utc_offset_minutes': 0,
      'business_date': now.toIso8601String().substring(0, 10),
      'reason': 'Exceso justificado y documentado',
      'preserved_effects': i.evidence.map((e) => e.toJson()).toList(),
      'recovery_effects': [
        ...i.recordedRecoveries.map((e) => e.toJson()),
        if (recoverStock)
          {...stock.toJson(), 'effect_id': const Uuid().v4(), 'delta': -1},
      ],
    });
  }

  Future<void> submit(OperacionVentaConciliadaPayload p) async {
    await commands.conciliar(
      ConciliarOperacionVentaCommand(
        payload: p,
        userId: h.context.userId,
        deviceId: h.context.deviceId,
      ),
    );
  }

  Future<void> accept(OperacionVentaConciliadaPayload p) => persistence
      .updateEventSyncStatus(p.eventId, 'delivered', serverSequence: 3);
}

void main() {
  test(
    'S16/S17 reconocimiento, ACK, eco y nueva consulta conservan libro físico',
    () async {
      final x = await ReconciliationHarness.create();
      addTearDown(x.h.close);
      final before = await x.h.store.readDeliveryState();
      final p = await x.payload();
      await x.submit(p);
      await x.submit(p);
      expect(await x.h.store.hasIncident(x.saleId), true);
      expect((await x.h.store.readDeliveryState()).inventory, before.inventory);
      await x.accept(p);
      await x.accept(p);
      final after = await x.h.store.readDeliveryState();
      expect(
        after.inventory[x.resourceId]!.recorded,
        before.inventory[x.resourceId]!.recorded,
      );
      expect(after.inventory[x.resourceId]!.localDifference, BigInt.zero);
      expect(await x.h.store.hasIncident(x.saleId), false);
      await x.submit(p);
      expect(await x.h.db.select(x.h.db.saleAdjustments).get(), hasLength(2));
      expect(
        (await x.store.incident(x.incidentId))!.resolutionEventId,
        p.eventId,
      );
    },
  );
  test(
    'S17 rechazo conserva recuperación; nueva intención reutiliza evidencia sin repetirla',
    () async {
      final x = await ReconciliationHarness.create();
      addTearDown(x.h.close);
      final before = (await x.h.store.readDeliveryState())
          .inventory[x.resourceId]!
          .recorded;
      final p = await x.payload(recoverStock: true);
      await x.submit(p);
      expect(
        (await x.h.store.readDeliveryState()).inventory[x.resourceId]!.recorded,
        before - BigInt.one,
      );
      await x.persistence.updateEventSyncStatus(
        p.eventId,
        'rejected',
        rejectionReason: 'Revisar motivo',
      );
      expect(await x.h.store.hasIncident(x.saleId), true);
      final retry = await x.payload();
      await x.submit(retry);
      await x.accept(retry);
      final after =
          (await x.h.store.readDeliveryState()).inventory[x.resourceId]!;
      expect(after.recorded, before - BigInt.one);
      expect(after.localDifference, BigInt.zero);
      expect(
        (await x.store.incident(x.incidentId))!.recordedRecoveries,
        hasLength(1),
      );
    },
  );
  test(
    'S17 revisión obsoleta y cambio de identidad no sobrescriben evidencia',
    () async {
      final x = await ReconciliationHarness.create();
      addTearDown(x.h.close);
      final p = await x.payload();
      final wrong = OperacionVentaConciliadaPayload.fromJson({
        ...p.toJson(),
        'expected_revision': 0,
      });
      await expectLater(x.submit(wrong), throwsFormatException);
      expect(
        await x.h.db.select(x.h.db.saleReconciliationEffects).get(),
        isEmpty,
      );
      final next = await x.payload();
      await x.submit(next);
      await expectLater(
        x.submit(
          OperacionVentaConciliadaPayload.fromJson({
            ...next.toJson(),
            'reason': 'Otra intención',
          }),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'S17 nota de crédito independiente actualiza cuenta sin fabricar abonos',
    () async {
      final x = await ReconciliationHarness.create(fixtureName: 'credit_void');
      addTearDown(x.h.close);
      final i = (await x.store.incident(x.incidentId))!;
      final repository = CustomerAccountRepositoryImpl(x.h.db);
      final before = await repository
          .watchAccount(i.loser.settlement.clienteId!)
          .first;
      final p = await x.payload();
      await x.submit(p);
      await x.accept(p);
      final after = await repository
          .watchAccount(i.loser.settlement.clienteId!)
          .first;
      expect(
        after.balanceMinor - before.balanceMinor,
        BigInt.from(i.loser.totalMinor),
      );
      expect(after.entries.where((e) => e.isReconciliation), hasLength(1));
      final summary = await ClienteResumenRepositoryImpl(
        x.h.db,
      ).watchResumen().first;
      expect(
        summary
            .singleWhere((c) => c.id == i.loser.settlement.clienteId)
            .saldoMinor,
        after.balanceMinor,
      );
      expect(await x.h.db.select(x.h.db.customerPayments).get(), isEmpty);
      expect(
        (await x.h.store.readDeliveryState())
            .creditReductions[x.saleId]!
            .localDifference,
        BigInt.zero,
      );
    },
  );
  test('S17 transferencia conservada no se duplica al reconocerla', () async {
    final x = await ReconciliationHarness.create(
      fixtureName: 'transfer_reference_no_drawer',
    );
    addTearDown(x.h.close);
    final transfers = TransferSummaryRepositoryImpl(x.h.db);
    final before = await transfers
        .watchTransferSummary(fromMs: 0, toMs: 9007199254740991)
        .first;
    final p = await x.payload();
    await x.submit(p);
    await x.accept(p);
    await x.accept(p);
    final after = await transfers
        .watchTransferSummary(fromMs: 0, toMs: 9007199254740991)
        .first;
    expect(after.netMinor, before.netMinor);
    expect(after.movements.length, before.movements.length);
    expect(await x.h.db.select(x.h.db.financialEntries).get(), isEmpty);
  });
  test(
    'S17 recuperación en caja actual se incluye en nuevo corte y conserva corte anterior',
    () async {
      final x = await ReconciliationHarness.create();
      addTearDown(x.h.close);
      const oldId = '00000000-0000-4000-8000-000000000801';
      const oldEvent = '00000000-0000-4000-8000-000000000802';
      await x.h.open(oldId, oldEvent);
      final cash = CajaCommandService(
        store: x.h.cashStore,
        events: x.h.events((_) async {}),
        context: x.h.context,
        config: x.h.config,
      );
      await cash.cerrar(
        const CerrarCajaCommand(sessionId: oldId, countedMinor: 0),
      );
      final closed = (await x.h.cashStore.find(oldId))!.close!.toJson();
      const currentId = '00000000-0000-4000-8000-000000000803';
      const currentEvent = '00000000-0000-4000-8000-000000000804';
      await x.h.open(currentId, currentEvent);
      final p = await x.payload();
      final money = p.preservedEffects.singleWhere((e) => e.ledger == 'cash');
      final recovery = OperacionVentaConciliadaPayload.fromJson({
        ...p.toJson(),
        'recovery_effects': [
          {
            ...money.toJson(),
            'effect_id': const Uuid().v4(),
            'delta': 500,
            'cash_session_id': currentId,
            'opening_event_id': currentEvent,
            'occurred_at_ms': p.occurredAtMs,
            'utc_offset_minutes': 0,
            'business_date': p.businessDate,
          },
        ],
      });
      await x.submit(recovery);
      final movements = await x.h.cashStore.movements(currentId);
      expect(movements, hasLength(1));
      expect(movements.single.sourceType, 'sale_reconciliation');
      expect(movements.single.amountMinor, 500);
      await x.accept(recovery);
      await x.accept(recovery);
      await cash.cerrar(
        const CerrarCajaCommand(sessionId: currentId, countedMinor: 500),
      );
      final cut = (await x.h.cashStore.find(currentId))!.close!;
      expect(cut.incomeMinor, '500');
      expect(cut.movements, hasLength(1));
      expect(
        jsonEncode((await x.h.cashStore.find(oldId))!.close!.toJson()),
        jsonEncode(closed),
      );
    },
  );
  test(
    'S17 una conciliación independiente no cambia la revisión comercial al reanudar',
    () async {
      final x = await ReconciliationHarness.create();
      addTearDown(x.h.close);
      final p = await x.payload();
      await x.submit(p);
      await x.accept(p);
      final handler = SaleAdjustmentEventHandler(
        store: x.h.store,
        cash: x.h.cashStore,
        config: x.h.config,
        isolatedSyncHarness: true,
      );
      final service = SaleAdjustmentCommandService(
        store: x.h.store,
        events: x.h.events(handler.apply),
        config: x.h.config,
        context: x.h.context,
        isolatedSyncHarness: true,
      );
      final original = (await x.h.store.confirmation(x.saleId))!;
      final line =
          object((original.payload['lines'] as List).first)['sale_item_id']
              as String;
      final next = await PrepareSaleAdjustment(service, x.h.cashStore)(
        saleId: x.saleId,
        expectedRevision: 1,
        voidSale: false,
        reason: 'Devolución del remanente oficial',
        action: 'refund_completed',
        selections: {line: (quantity: 1, destination: 'restock')},
      );
      await x.h.execute(next.toJson(), commands: service);
      final event = (await x.persistence.eventById(next.eventId))!;
      expect(
        await SaleAdjustmentPendingEventValidator(
          x.persistence,
        ).validate(event, {}),
        isNull,
      );
    },
  );
  test(
    'S17 fallo durante aceptación revierte metadata, resolución y reconocimiento',
    () async {
      final x = await ReconciliationHarness.create();
      addTearDown(x.h.close);
      final p = await x.payload();
      await x.submit(p);
      await x.h.db.customStatement(
        "CREATE TRIGGER fail_rec BEFORE UPDATE ON sale_delivery_incidents BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      await expectLater(x.accept(p), throwsA(anything));
      expect(
        (await x.persistence.eventById(p.eventId))!.deliveryStatus,
        'pending',
      );
      expect(await x.h.store.hasIncident(x.saleId), true);
      await x.h.db.customStatement('DROP TRIGGER fail_rec');
      await x.accept(p);
      expect(await x.h.store.hasIncident(x.saleId), false);
    },
  );
}
