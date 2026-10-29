import 'package:pos_flutter/application/commands/caja/caja_command_service.dart';
import 'package:pos_flutter/application/commands/caja/cerrar_caja_command.dart';
import 'dart:convert';
import 'package:drift/native.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/models/sale_adjustment_outcome.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/sale_adjustment_repository_impl.dart';
import 'package:pos_flutter/data/repositories/customer_account_repository_impl.dart';
import 'package:pos_flutter/domain/ventas/sale_adjustment_status.dart';
import '../../../support/sale_adjustment_harness.dart';

void main() {
  for (final f in adjustmentFixtures().where(
    (f) => object(f['payload'])['kind'] == 'return',
  )) {
    test('2C SQLite ${f['name']}', () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      await h.seed(f);
      await h.replayHistory(f);
      final before = await h.snapshot();
      final p = object(f['payload']);
      if (f['valid'] != true) {
        await expectLater(Future.sync(() => h.execute(p)), throwsA(anything));
        expect(await h.snapshot(), before);
        return;
      }
      final originalSales = await h.db.select(h.db.sales).get();
      final originalItems = await h.db.select(h.db.saleItems).get();
      final originalPayments = await h.db.select(h.db.salePayments).get();
      final stockBefore = await h.db.select(h.db.inventoryBalances).get();
      final observed = SaleAdjustmentRepositoryImpl(h.db)
          .watchSales()
          .firstWhere(
            (s) => s.single.revision == (f['history'] as List).length + 1,
          );
      await h.execute(p);
      final sale = (await observed).single;
      expect(
        sale.status,
        sale.remainingQuantities.values.every((q) => q == 0)
            ? SaleAdjustmentStatus.fullyReturned
            : SaleAdjustmentStatus.partiallyReturned,
      );
      expect(sale.adjustments.last.amountMinor, p['total_minor']);
      expect(
        sale.adjustments.last.lines.map((l) => l.recoveredCostMinor),
        (p['lines'] as List).map((l) => l['recovered_cost_minor']),
      );
      final after = await h.snapshot();
      expect(
        (await h.execute(p)).status,
        SaleAdjustmentOutcomeStatus.duplicate,
      );
      expect(await h.snapshot(), after);
      expect(await h.db.select(h.db.sales).get(), originalSales);
      expect(await h.db.select(h.db.saleItems).get(), originalItems);
      expect(await h.db.select(h.db.salePayments).get(), originalPayments);
      for (final b in stockBefore) {
        final delta = (p['lines'] as List)
            .expand((l) => l['stock'] as List)
            .where((m) => m['inventory_item_id'] == b.inventoryItemId)
            .fold(0, (n, m) => n + (m['quantity_atomic'] as int));
        final current =
            await (h.db.select(h.db.inventoryBalances)
                  ..where((t) => t.inventoryItemId.equals(b.inventoryItemId)))
                .getSingle();
        expect(current.quantityOnHandAtomic, b.quantityOnHandAtomic + delta);
      }
      expect(
        (await h.db.select(h.db.products).get()).every((p) => !p.active),
        isTrue,
      );
      expect(
        (await h.db.select(h.db.inventoryItems).get()).every((p) => !p.active),
        isTrue,
      );
      expect(await h.db.select(h.db.cashMovements).get(), isEmpty);
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
      expect(
        await h.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    });
  }
  test(
    'A09/A10 sucesivas 33/34/33: remanente cero, importe 100 y stock histórico exacto',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final fs =
          [
                'measured_first_33',
                'measured_second_34_not_33',
                'measured_final_exact_100',
              ]
              .map(
                (name) =>
                    adjustmentFixtures().firstWhere((f) => f['name'] == name),
              )
              .toList();
      await h.seed(fs.first);
      for (final f in fs) {
        await h.execute(object(f['payload']));
      }
      final sale = (await SaleAdjustmentRepositoryImpl(
        h.db,
      ).watchSales().first).single;
      expect(sale.adjustments.map((a) => a.amountMinor), [33, 34, 33]);
      expect(sale.remainingQuantities.values.single, 0);
      expect(sale.status, SaleAdjustmentStatus.fullyReturned);
      expect(
        (await h.db.select(h.db.inventoryMovements).get()).fold(
          0,
          (n, m) => n + m.quantityDeltaAtomic,
        ),
        0,
      );
    },
  );
  test(
    'A21 fechas congeladas al cruzar medianoche sin alterar original',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final fs = ['measured_first_33', 'measured_second_34_not_33']
          .map(
            (name) => adjustmentFixtures().firstWhere((f) => f['name'] == name),
          )
          .toList();
      await h.seed(fs.first);
      final first = {
        ...object(fs.first['payload']),
        'occurred_at_ms': 1793253599999,
        'business_date': '2026-10-28',
      };
      final second = {
        ...object(fs.last['payload']),
        'occurred_at_ms': 1793253600001,
        'business_date': '2026-10-29',
      };
      final original = (await SaleAdjustmentRepositoryImpl(
        h.db,
      ).watchSales().first).single.original.createdAt;
      await h.execute(first);
      await h.execute(second);
      final sale = (await SaleAdjustmentRepositoryImpl(
        h.db,
      ).watchSales().first).single;
      expect(sale.adjustments.map((a) => a.businessDate), [
        '2026-10-28',
        '2026-10-29',
      ]);
      expect(sale.original.createdAt, original);
    },
  );
  test(
    'A17 parcial crédito con abonos: FIFO sobre netos, sin alterar documentos',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().firstWhere(
        (f) => f['name'] == 'credit_return_reduce_charge_no_refund',
      );
      await h.seed(f);
      await h.creditWithPayment(f);
      final debts = await h.db.select(h.db.creditSales).get();
      final payments = await h.db.select(h.db.customerPayments).get();
      await h.execute(object(f['payload']));
      final account = await CustomerAccountRepositoryImpl(
        h.db,
      ).watchAccount(object(f['original'])['cliente_id'] as String).first;
      expect(account.balanceMinor, BigInt.zero);
      expect(account.allocations.map((a) => a.amountMinor), [500, 1000]);
      expect(
        (await h.db.select(h.db.creditAllocations).get()).map(
          (a) => a.amountMinor,
        ),
        [500, 1000],
      );
      expect(await h.db.select(h.db.creditSales).get(), debts);
      expect(await h.db.select(h.db.customerPayments).get(), payments);
      expect(await h.db.select(h.db.cashMovements).get(), isEmpty);
    },
  );

  test(
    'A17 devolución total tras parcial libera saldo a favor y conserva abonos',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().firstWhere(
        (f) => f['name'] == 'credit_return_reduce_charge_no_refund',
      );
      await h.seed(f);
      await h.creditWithPayment(f);
      final p = object(f['payload']);
      await h.execute(p);
      final next = object(jsonDecode(jsonEncode(p)));
      next['operation_id'] = '00000000-0000-4000-8000-000000000920';
      next['event_id'] = '00000000-0000-4000-8000-000000000921';
      next['expected_revision'] = 1;
      next['previous_adjustment_event_id'] = p['event_id'];
      next['dependency_event_ids'] = [
        ...p['dependency_event_ids'] as List,
        p['event_id'],
      ];
      (next['lines'] as List)[0]['stock'][0]['movement_id'] =
          '00000000-0000-4000-8000-000000000922';
      await h.execute(next);
      final account = await CustomerAccountRepositoryImpl(
        h.db,
      ).watchAccount(object(f['original'])['cliente_id'] as String).first;
      expect(account.balanceMinor, BigInt.from(500));
      expect(account.allocations.single.amountMinor, 1000);
      expect(await h.db.select(h.db.cashMovements).get(), isEmpty);
      expect(
        (await SaleAdjustmentRepositoryImpl(h.db).watchSales().first)
            .firstWhere((s) => s.original.id == p['sale_id'])
            .status,
        SaleAdjustmentStatus.fullyReturned,
      );
    },
  );
  test(
    'A27 dos formularios distintos concurrentes: una revisión ganadora',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().firstWhere(
        (f) => f['name'] == 'measured_first_33',
      );
      await h.seed(f);
      final p = object(f['payload']);
      final next = object(jsonDecode(jsonEncode(p)));
      next['operation_id'] = '00000000-0000-4000-8000-000000000930';
      next['event_id'] = '00000000-0000-4000-8000-000000000931';
      (next['lines'] as List)[0]['stock'][0]['movement_id'] =
          '00000000-0000-4000-8000-000000000932';
      Future<bool> run(Map<String, Object?> j) async {
        try {
          await h.execute(j);
          return true;
        } on FormatException {
          return false;
        }
      }

      final results = await Future.wait([run(p), run(next)]);
      expect(results.where((r) => r), hasLength(1));
      expect(await h.db.select(h.db.saleAdjustments).get(), hasLength(1));
    },
  );
  test(
    'A28 devolución pagada: rollback de cajón y cierre posterior coherente',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final base = adjustmentFixtures().firstWhere(
        (f) => f['name'] == 'measured_first_33',
      );
      final cash = adjustmentFixtures().first;
      final p = object(jsonDecode(jsonEncode(base['payload'])));
      p['settlement'] = {
        ...object(p['settlement']),
        'cash_enabled': true,
        'cash': object(object(cash['payload'])['settlement'])['cash'],
      };
      p['dependency_event_ids'] = [
        ...p['dependency_event_ids'] as List,
        object(cash['cash_context'])['opening_event_id'],
      ];
      final f = {...base, 'payload': p, 'cash_context': cash['cash_context']};
      await h.seed(f);
      final before = await h.snapshot();
      await h.db.customStatement(
        "CREATE TEMP TRIGGER inject_failure AFTER INSERT ON cash_movements BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      await expectLater(h.execute(p), throwsA(anything));
      expect(await h.snapshot(), before);
      await h.db.customStatement('DROP TRIGGER inject_failure');
      await h.execute(p);
      final binding = object(object(p['settlement'])['cash']);
      await CajaCommandService(
        store: h.cashStore,
        events: h.events(h.handler.apply),
        context: h.context,
        config: h.config,
      ).cerrar(
        CerrarCajaCommand(
          sessionId: binding['session_id'] as String,
          countedMinor: 0,
        ),
      );
      final session = await h.cashStore.find(binding['session_id'] as String);
      expect(session!.close!.expenseMinor, '33');
      expect(session.close!.movements.single.sourceType, 'sale_adjustment');
    },
  );
  test(
    'A25/A27 doble ejecución simultánea y dos formularios sobre misma revisión',
    () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final f = adjustmentFixtures().firstWhere(
        (f) => f['name'] == 'measured_first_33',
      );
      await h.seed(f);
      final p = object(f['payload']);
      final results = await Future.wait([h.execute(p), h.execute(p)]);
      expect(results.map((r) => r.status).toSet(), {
        SaleAdjustmentOutcomeStatus.accepted,
        SaleAdjustmentOutcomeStatus.duplicate,
      });
      final before = await h.snapshot();
      final other = object(jsonDecode(jsonEncode(p)));
      other['operation_id'] = '00000000-0000-4000-8000-000000000910';
      other['event_id'] = '00000000-0000-4000-8000-000000000911';
      for (final l in other['lines'] as List) {
        for (final m in l['stock'] as List) {
          m['movement_id'] = '00000000-0000-4000-8000-000000000912';
        }
      }
      await expectLater(h.execute(other), throwsFormatException);
      expect(await h.snapshot(), before);
    },
  );
  test(
    'A25 reinicio antes del retry y después del commit conserva IDs e intención',
    () async {
      final first = await SaleAdjustmentHarness.create();
      final dir = first.directory;
      final f = adjustmentFixtures().firstWhere(
        (f) => f['name'] == 'measured_first_33',
      );
      await first.seed(f);
      final p = object(f['payload']);
      final before = await first.snapshot();
      await expectLater(
        first.execute(
          p,
          commands: first.service(
            apply: (e) async {
              await first.handler.apply(e);
              throw StateError('respuesta fallida antes del commit');
            },
          ),
        ),
        throwsStateError,
      );
      expect(await first.snapshot(), before);
      await first.db.close();
      await first.config.dispose();
      final second = SaleAdjustmentHarness(
        AppDatabase.forTesting(NativeDatabase(File('${dir.path}/test.sqlite'))),
        dir,
      );
      final saved = await second.service().recoverIntention(
        p['operation_id'] as String,
      );
      expect(saved!.payload, p);
      expect(
        (await second.execute(saved.payload)).status,
        SaleAdjustmentOutcomeStatus.accepted,
      );
      final after = await second.snapshot();
      await second.db.close();
      await second.config.dispose();
      final third = SaleAdjustmentHarness(
        AppDatabase.forTesting(NativeDatabase(File('${dir.path}/test.sqlite'))),
        dir,
      );
      addTearDown(third.close);
      expect(
        (await third.execute(p)).status,
        SaleAdjustmentOutcomeStatus.duplicate,
      );
      expect(await third.snapshot(), after);
    },
  );
  for (final stage in [
    'sale_adjustment_lines',
    'inventory_movements',
    'inventory_balances',
    'sale_credit_reductions',
    'credit_allocations',
  ]) {
    test('A28 devolución rollback tras $stage', () async {
      final h = await SaleAdjustmentHarness.create();
      addTearDown(h.close);
      final credit = [
        'sale_credit_reductions',
        'credit_allocations',
      ].contains(stage);
      final f = adjustmentFixtures().firstWhere(
        (f) =>
            f['name'] ==
            (credit
                ? 'credit_return_reduce_charge_no_refund'
                : 'measured_first_33'),
      );
      await h.seed(f);
      if (credit) await h.creditWithPayment(f);
      final before = await h.snapshot();
      await h.db.customStatement(
        "CREATE TEMP TRIGGER inject_failure AFTER ${stage == 'inventory_balances' ? 'UPDATE' : 'INSERT'} ON $stage BEGIN SELECT RAISE(ABORT,'injected'); END",
      );
      await expectLater(h.execute(object(f['payload'])), throwsA(anything));
      expect(await h.snapshot(), before);
      await h.db.customStatement('DROP TRIGGER inject_failure');
      await h.execute(object(f['payload']));
    });
  }
}
