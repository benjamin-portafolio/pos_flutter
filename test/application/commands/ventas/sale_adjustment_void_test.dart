import 'package:pos_flutter/data/repositories/customer_account_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/models/sale_adjustment_outcome.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/local/drift/drift_cash_projection_store.dart';
import 'package:pos_flutter/data/repositories/cash_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_adjustment_repository_impl.dart';
import 'package:pos_flutter/domain/ventas/sale_adjustment_status.dart';
import '../../../support/sale_adjustment_harness.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  for (final f in adjustmentFixtures().where(
    (f) => object(f['payload'])['kind'] == 'void',
  )) {
    test('2B SQLite ${f['name']}', () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      await h.seed(f);
      await h.replayHistory(f);
      final before = await h.snapshot();
      final closedBefore = await (h.db.select(
        h.db.cashSessions,
      )..where((t) => t.status.equals('closed'))).get();
      final p = object(f['payload']);
      if (f['valid'] != true) {
        await expectLater(Future.sync(() => h.execute(p)), throwsA(anything));
        expect(await h.snapshot(), before);
        return;
      }
      expect((await h.execute(p)).status, SaleAdjustmentOutcomeStatus.accepted);
      final after = await h.snapshot();
      expect(
        (await h.execute(p)).status,
        SaleAdjustmentOutcomeStatus.duplicate,
      );
      expect(await h.snapshot(), after);
      await h.handler.apply(
        (await h.store.recoverIntention(p['operation_id'] as String))!,
      );
      expect(await h.snapshot(), after);
      final sale = (await SaleAdjustmentRepositoryImpl(
        h.db,
      ).watchSales().first).single;
      expect(sale.status, SaleAdjustmentStatus.voided);
      expect(sale.original.totalMinor, object(f['original'])['total_minor']);
      expect(sale.adjustments.single.amountMinor, p['total_minor']);
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
      expect(
        (await h.db.eventDao.obtenerEventoPorId(
          p['event_id'] as String,
        ))!.deliveryStatus,
        'not_required',
      );
      for (final line in p['lines'] as List) {
        for (final raw in line['stock'] as List) {
          final m = object(raw);
          final stored =
              await (h.db.select(h.db.inventoryMovements)..where(
                    (t) => t.movementId.equals(m['movement_id'] as String),
                  ))
                  .getSingle();
          expect(stored.quantityDeltaAtomic, m['quantity_atomic']);
          expect(stored.reversalOfMovementId, m['original_movement_id']);
          expect(stored.movementType, 'sale_void_restock');
        }
      }
      final cash = object(p['settlement'])['cash'];
      if (cash != null) {
        final b = object(cash);
        final movements = await DriftCashProjectionStore(
          h.db,
        ).movements(b['session_id'] as String);
        expect(movements.single.sourceType, 'sale_adjustment');
        expect(movements.single.direction, 'out');
        expect(movements.single.amountMinor, p['total_minor']);
        final sessions = await CashRepositoryImpl(h.db).watchSessions().first;
        expect(
          sessions
              .where((s) => s.id == b['session_id'])
              .single
              .movements
              .single
              .sourceId,
          p['operation_id'],
        );
      }
      expect(
        await (h.db.select(
          h.db.cashSessions,
        )..where((t) => t.status.equals('closed'))).get(),
        closedBefore,
      );
      expect(
        await h.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });
  }
  for (final stage in [
    'sale_adjustments',
    'sale_adjustment_lines',
    'inventory_movements',
    'inventory_balances',
    'cash_movements',
    'sale_credit_reductions',
  ]) {
    test('2B rollback SQLite después de $stage; intención recuperable', () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().firstWhere(
        (f) =>
            f['name'] ==
            (stage == 'sale_credit_reductions'
                ? 'credit_void'
                : 'void_cash_net_not_received_plus_change'),
      );
      await h.seed(f);
      final before = await h.snapshot();
      await h.db.customStatement(
        "CREATE TEMP TRIGGER inject_failure AFTER ${stage == 'inventory_balances' ? 'UPDATE' : 'INSERT'} ON $stage BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      final p = object(f['payload']);
      await expectLater(h.execute(p), throwsA(anything));
      expect(await h.snapshot(), before);
      final recovered = await h.service().recoverIntention(
        p['operation_id'] as String,
      );
      expect(recovered, isNotNull);
      expect(recovered!.payload, p);
      await h.db.customStatement('DROP TRIGGER inject_failure');
      expect(
        (await h.execute(recovered.payload)).status,
        SaleAdjustmentOutcomeStatus.accepted,
      );
    });
  }
  test(
    '2B gate server_sync desde servicio y handler antes de escrituras',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().first;
      await h.seed(f);
      final entry = h.prepare(f);
      final before = await h.snapshot();
      h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
      await expectLater(h.execute(object(f['payload'])), throwsStateError);
      await expectLater(h.handler.apply(entry.event), throwsStateError);
      final returned = object(
        adjustmentFixtures().firstWhere(
          (f) => f['name'] == 'measured_first_33',
        )['payload'],
      );
      await expectLater(h.execute(returned), throwsStateError);
      expect(await h.db.select(h.db.saleAdjustmentIntents).get(), isEmpty);
      expect(await h.snapshot(), before);
    },
  );
  test(
    '2B IDs estables con milisegundos, colisiones y revisión tras éxito',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().first;
      await h.seed(f);
      final p = {...object(f['payload']), 'occurred_at_ms': 1793203200123};
      await h.execute(p);
      final before = await h.snapshot();
      expect(
        (await h.execute(p)).status,
        SaleAdjustmentOutcomeStatus.duplicate,
      );
      for (final collision in [
        {...p, 'reason': 'Otra intención'},
        {...p, 'event_id': '00000000-0000-4000-8000-000000000999'},
        {...p, 'operation_id': '00000000-0000-4000-8000-000000000998'},
      ]) {
        await expectLater(h.execute(collision), throwsStateError);
        expect(await h.snapshot(), before);
      }
    },
  );
  test(
    'A04 crédito con abonos: deuda original intacta, FIFO a otra venta y saldo a favor',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().firstWhere(
        (f) => f['name'] == 'credit_void',
      );
      await h.seed(f);
      await h.creditWithPayment(f);
      final original = object(f['original']);
      final debts = await h.db.select(h.db.creditSales).get();
      final payments = await h.db.select(h.db.customerPayments).get();
      expect((await h.db.select(h.db.creditAllocations).get()).length, 2);
      final changed = CustomerAccountRepositoryImpl(h.db)
          .watchAccount(original['cliente_id'] as String)
          .firstWhere((a) => a.balanceMinor == BigInt.from(500));
      await h.execute(object(f['payload']));
      final account = await changed;
      expect(
        account.allocations.single.creditId,
        '00000000-0000-4000-8000-000000000900',
      );
      expect(account.allocations.single.amountMinor, 1000);
      expect(
        account.availableMinor(
          account.entries.where((e) => e.isPayment).single,
        ),
        500,
      );
      expect(await h.db.select(h.db.creditSales).get(), debts);
      expect(await h.db.select(h.db.customerPayments).get(), payments);
      final allocations = await h.db.select(h.db.creditAllocations).get();
      expect(allocations.single.amountMinor, 1000);
      expect(await h.db.select(h.db.cashMovements).get(), isEmpty);
    },
  );
  test('A23 efectivo habilitado sin apertura rechaza sin efectos', () async {
    final h = await SaleAdjustmentHarness.create();
    addTearDown(h.close);
    final f = {
      ...adjustmentFixtures().first,
      'cash_context': {
        'enabled': true,
        'open': false,
        'session_id': null,
        'opening_event_id': null,
      },
    };
    await h.seed(f);
    final before = await h.snapshot();
    await expectLater(h.execute(object(f['payload'])), throwsFormatException);
    expect(await h.snapshot(), before);
  });
  test('2B inexistente o borrador no genera efectos comerciales', () async {
    final h = await SaleAdjustmentHarness.create();
    addTearDown(h.close);
    final f = adjustmentFixtures().first;
    final p = object(f['payload']);
    final before = await h.snapshot();
    await expectLater(h.execute(p), throwsStateError);
    expect(await h.snapshot(), before);
    await h.db
        .into(h.db.sales)
        .insert(
          SalesCompanion.insert(
            id: p['sale_id'] as String,
            userId: 'operator',
            deviceId: 'terminal',
            totalMinor: 0,
            createdAtLocal: DateTime.now(),
            updatedAtLocal: DateTime.now(),
          ),
        );
    final draft = await h.snapshot();
    await expectLater(h.execute(p), throwsStateError);
    expect(await h.snapshot(), draft);
  });
}
