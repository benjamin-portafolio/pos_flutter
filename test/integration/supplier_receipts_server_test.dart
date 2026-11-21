import 'package:pos_flutter/application/commands/proveedores/close_supplier_order_command.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_closed_payload.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_order_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import '../support/product_supplier_harness.dart';
import '../support/supplier_order_harness.dart';
import '../application/commands/proveedores/supplier_receipt_local_test.dart'
    show confirmedOrder, receipt;

void main() {
  final url = Platform.environment['POS_SUPPLIER_SYNC_URL'];
  test(
    'S4 HTTP/PG: venta intermedia, dos recepciones concurrentes, rechazo tardío, eco, reapertura y replay',
    () async {
      final dir = await Directory.systemTemp.createTemp('receipt-http-');
      final run = const Uuid().v4();
      ProductSupplierHarness terminal(String id) => ProductSupplierHarness(
        mode: AppMode.serverSync,
        context: LocalCommandContext(
          deviceId: 's4-$run-$id',
          userId: 'synthetic-receipts',
        ),
        database: AppDatabase.forTesting(
          NativeDatabase(File('${dir.path}/$id.sqlite')),
        ),
      );
      var a = terminal('a'), b = terminal('b');
      Future<void> sync(ProductSupplierHarness h) async {
        for (var i = 0; i < 20; i++) {
          final pre = await h.tracking.preflight(url!).preflightPendingEvents();
          if (pre.requiresFullPullBeforePush) {
            await h.tracking.pull(url).pullAvailableEvents();
            continue;
          }
          final result = await h.tracking.push(url).pushPendingEvents();
          await h.tracking.pull(url).pullAvailableEvents();
          if (result.pending == 0 &&
              (await h.tracking.history.pendingEvents()).isEmpty) {
            return;
          }
        }
        fail('No converge');
      }

      Future<int> stock(ProductSupplierHarness h, String resource) async =>
          (await h.db.select(h.db.inventoryBalances).get())
              .singleWhere((b) => b.inventoryItemId == resource)
              .quantityOnHandAtomic;
      Future<void> sell(
        ProductSupplierHarness h,
        String variant,
        int count,
      ) async {
        if (await h.tracking.cashStore.current(h.tracking.context.deviceId) ==
            null) {
          await h.tracking.cash.abrir(
            AbrirCajaCommand(sessionId: const Uuid().v4(), openingMinor: 0),
          );
        }
        for (var i = 0; i < count; i++) {
          await h.tracking.drafts.agregar(
            AgregarProductoBorradorCommand(variantId: variant),
          );
        }
        final draft = (await h.db.select(h.db.sales).get()).singleWhere(
          (s) => s.status == 'borrador',
        );
        await h.tracking.sales.confirmar(
          ConfirmarVentaCommand(
            saleId: draft.id,
            expectedDraftEventId: draft.lastEventId!,
            expectedTotalMinor: draft.totalMinor,
          ),
        );
      }

      try {
        final id = await confirmedOrder(a);
        await sync(a);
        await b.tracking.pull(url!).pullAvailableEvents();
        final line = (await a.tracking.orders.find(id))!.document.items.single;
        await sell(a, line.variantId, 2);
        await sync(a);
        await b.tracking.pull(url).pullAvailableEvents();
        expect(await stock(a, line.inventoryItemId), 1);
        final ca = await receipt(a, id, 3), cb = await receipt(b, id, 3);
        await a.orders.receive(ca);
        await b.orders.receive(cb);
        await sync(a);
        final loser = await b.tracking.push(url).pushPendingEvents();
        expect(loser.conflicts, 1);
        await b.tracking.pull(url).pullAvailableEvents();
        expect(await stock(a, line.inventoryItemId), 4);
        expect(await stock(b, line.inventoryItemId), 4);
        expect(
          (await b.db.select(b.db.supplierReceipts).get())
              .where((r) => r.orderId == id)
              .length,
          1,
        );
        expect(
          (await b.tracking.orders.candidates())
              .firstWhere((c) => c.variantId == line.variantId)
              .pendingAtomic,
          1,
        );
        final last = await receipt(b, id, 1);
        await b.orders.receive(last);
        await sync(b);
        await a.tracking.pull(url).pullAvailableEvents();
        expect(await stock(a, line.inventoryItemId), 5);
        expect((await a.tracking.orders.find(id))!.status, 'received');
        // Same event after a later receipt must be a no-op, even via the processor.
        final accepted = (await a.tracking.history.eventById(ca.eventId))!;
        await a.tracking.processor.apply(accepted);
        expect(await stock(a, line.inventoryItemId), 5);
        // A rejected receipt with a later physical sale loses only its own delta.
        final d = await a.newOrder(
          supplierId: (await a.tracking.orders.find(id))!.document.supplierId,
          quantity: 4,
        );
        await a.orders.save(await a.orderCommand(d));
        await a.orders.save(
          await a.orderCommand(await a.based(d.orderId), confirm: true),
        );
        await sync(a);
        final invalid = SupplierOrderCommandService(
          store: a.tracking.orders,
          events: a.tracking.events,
          context: LocalCommandContext(
            deviceId: a.tracking.context.deviceId,
            userId: ' ',
          ),
          requireCompatible: () async {},
        );
        final bad = await receipt(a, d.orderId, 3);
        await invalid.receive(bad);
        final partial = (await a.tracking.orders.find(d.orderId))!;
        final close = CloseSupplierOrderCommand(
          eventId: const Uuid().v4(),
          payload: SupplierOrderClosedPayload.fromJson({
            'contract_version': 1,
            'order_id': d.orderId,
            'base_event_id': partial.lastEventId,
            'occurred_at_ms': 700,
            'items': [
              {
                'order_item_id': partial.document.items.single.id,
                'closed_quantity_atomic': 1,
              },
            ],
          }),
        );
        await a.orders.closeRemainder(close);
        await sell(a, line.variantId, 2);
        final report = await a.tracking.push(url).pushPendingEvents();
        expect(report.rejected, 1);
        expect(report.conflicts, 1);
        final failures = await DriftSupplierOrderRepository(
          a.db,
        ).watchFailedAttempts().first;
        expect(
          failures.any((f) => f.orderId == d.orderId && !f.canRecoverDraft),
          true,
        );
        await sync(a);
        await b.tracking.pull(url).pullAvailableEvents();
        expect(await stock(a, line.inventoryItemId), 3);
        expect(await stock(b, line.inventoryItemId), 3);
        expect((await a.tracking.orders.find(d.orderId))!.status, 'confirmed');
        expect(
          (await a.db.select(a.db.supplierReceipts).get()).any(
            (r) => r.id == bad.payload.receiptId,
          ),
          false,
        );
        // Exact single-receipt case: live 3, order 4, sale 2, receipt 4 => 5.
        final exact = await a.newOrder(
          supplierId: partial.document.supplierId,
          quantity: 4,
        );
        await a.orders.save(await a.orderCommand(exact));
        await a.orders.save(
          await a.orderCommand(await a.based(exact.orderId), confirm: true),
        );
        await sync(a);
        await sell(a, line.variantId, 2);
        await sync(a);
        expect(await stock(a, line.inventoryItemId), 1);
        await a.orders.receive(await receipt(a, exact.orderId, 4));
        await sync(a);
        expect(await stock(a, line.inventoryItemId), 5);
        await a.dispose();
        a = terminal('a');
        await a.orders.receive(
          last,
        ); // original persisted result from b is also in a's history
        expect(await stock(a, line.inventoryItemId), 5);
        final c = terminal('c');
        try {
          await c.tracking.pull(url).pullAvailableEvents();
          expect(await stock(c, line.inventoryItemId), 5);
          final receipts = (await c.db.select(c.db.supplierReceipts).get())
              .where((r) => r.orderId == id)
              .toList();
          expect(receipts.length, 2);
          expect(receipts.every((r) => r.lastServerSequence != null), true);
          final aItems =
              (await a.db.select(a.db.supplierReceiptItems).get())
                  .where((r) => r.orderId == id)
                  .map((r) => jsonEncode(r.toJson()))
                  .toList()
                ..sort();
          final cItems =
              (await c.db.select(c.db.supplierReceiptItems).get())
                  .where((r) => r.orderId == id)
                  .map((r) => jsonEncode(r.toJson()))
                  .toList()
                ..sort();
          expect(aItems, cItems);
          Future<Map<String, List<String>>> audit(
            ProductSupplierHarness h,
          ) async {
            final result = <String, List<String>>{};
            for (final table in [
              'supplier_orders',
              'supplier_order_items',
              'supplier_receipts',
              'supplier_receipt_items',
              'inventory_balances',
              'inventory_movements',
            ]) {
              final rows =
                  (await h.db.customSelect('SELECT * FROM $table').get())
                      .map((r) => r.data)
                      .where(
                        (r) => table == 'supplier_orders'
                            ? {id, d.orderId, exact.orderId}.contains(r['id'])
                            : table.startsWith('supplier_')
                            ? {
                                id,
                                d.orderId,
                                exact.orderId,
                              }.contains(r['order_id'])
                            : r['inventory_item_id'] == line.inventoryItemId,
                      )
                      .map(jsonEncode)
                      .toList()
                    ..sort();
              result[table] = rows;
            }
            return result;
          }

          expect(await audit(a), await audit(c));
          expect(
            (await c.tracking.orders.candidates())
                .firstWhere((v) => v.variantId == line.variantId)
                .pendingAtomic,
            (await a.tracking.orders.candidates())
                .firstWhere((v) => v.variantId == line.variantId)
                .pendingAtomic,
          );
        } finally {
          await c.dispose();
        }
      } finally {
        await a.dispose();
        await b.dispose();
        await dir.delete(recursive: true);
      }
    },
    skip: url == null ? 'Requiere HTTP/PG aislado' : false,
  );
}
