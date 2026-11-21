import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/proveedores/cancel_supplier_order_command.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:uuid/uuid.dart';
import '../support/product_supplier_harness.dart';
import '../support/supplier_order_harness.dart';
import '../application/commands/proveedores/supplier_order_local_test.dart'
    show seedOrders;

void main() {
  final url = Platform.environment['POS_SUPPLIER_SYNC_URL'];
  test(
    'S3 HTTP/PostgreSQL: dos clientes, dependencia, eco/replay, conflicto/rechazo, solapamiento y stock intacto',
    () async {
      final dir = await Directory.systemTemp.createTemp('orders-http-s3-');
      final run = const Uuid().v4();
      ProductSupplierHarness terminal(String id) => ProductSupplierHarness(
        mode: AppMode.serverSync,
        database: AppDatabase.forTesting(
          NativeDatabase(File('${dir.path}/$id.sqlite')),
        ),
        context: LocalCommandContext(
          deviceId: 's3-$run-$id',
          userId: 'synthetic-orders',
        ),
      );
      var a = terminal('a');
      var b = terminal('b');
      Future<void> sync(ProductSupplierHarness h) async {
        for (var i = 0; i < 20; i++) {
          final pre = await h.tracking.preflight(url!).preflightPendingEvents();
          if (pre.requiresFullPullBeforePush) {
            await h.tracking.pull(url).pullAvailableEvents();
            continue;
          }
          final push = await h.tracking.push(url).pushPendingEvents();
          await h.tracking.pull(url).pullAvailableEvents();
          if (push.pending == 0 &&
              (await h.tracking.history.pendingEvents()).isEmpty) {
            return;
          }
        }
        fail('No converge');
      }

      Future<String> stock(ProductSupplierHarness h) async => jsonEncode([
        (await h.db.select(h.db.inventoryBalances).get())
            .map((r) => r.toJson())
            .toList(),
        (await h.db.select(h.db.inventoryMovements).get())
            .map((r) => r.toJson())
            .toList(),
      ]);
      try {
        final supplier = await seedOrders(a);
        await sync(a);
        await b.tracking.pull(url!).pullAvailableEvents();
        final before = await stock(a);
        final doc = await a.newOrder(supplierId: supplier);
        await a.orders.save(await a.orderCommand(doc));
        await a.orders.save(
          await a.orderCommand(await a.based(doc.orderId), confirm: true),
        );
        await sync(a);
        await b.tracking.pull(url).pullAvailableEvents();
        expect(
          (await b.tracking.orders.find(doc.orderId))!.status,
          'confirmed',
        );
        expect(
          (await b.tracking.orders.candidates())
              .firstWhere((c) => c.supplierId == supplier)
              .suggestedAtomic,
          0,
        );
        expect(await stock(a), before);
        // Same confirmed base on two clients: cancellation wins once, stale operation conflicts.
        final abase = (await a.tracking.orders.find(doc.orderId))!;
        final bbase = (await b.tracking.orders.find(doc.orderId))!;
        final ca = CancelSupplierOrderCommand(
          eventId: const Uuid().v4(),
          orderId: doc.orderId,
          baseEventId: abase.lastEventId!,
          occurredAtMs: 200,
        );
        final cb = CancelSupplierOrderCommand(
          eventId: const Uuid().v4(),
          orderId: doc.orderId,
          baseEventId: bbase.lastEventId!,
          occurredAtMs: 201,
        );
        await a.orders.cancel(ca);
        await b.orders.cancel(cb);
        await sync(a);
        final rejected = await b.tracking.push(url).pushPendingEvents();
        expect(rejected.conflicts, 1);
        await b.tracking.pull(url).pullAvailableEvents();
        expect(
          (await b.tracking.history.eventById(cb.eventId))!.deliveryStatus,
          'conflict',
        );
        expect(
          (await b.tracking.orders.find(doc.orderId))!.status,
          'cancelled',
        );
        // Independent offline documents may overlap; neither is cancelled automatically.
        final d1 = await a.newOrder(supplierId: supplier),
            d2 = await b.newOrder(supplierId: supplier);
        await a.orders.save(await a.orderCommand(d1));
        await b.orders.save(await b.orderCommand(d2));
        await a.orders.save(
          await a.orderCommand(await a.based(d1.orderId), confirm: true),
        );
        await b.orders.save(
          await b.orderCommand(await b.based(d2.orderId), confirm: true),
        );
        await sync(a);
        await sync(b);
        await a.tracking.pull(url).pullAvailableEvents();
        final open =
            (await DriftSupplierOrderRepository(
              a.db,
            ).watchOrders().first).where(
              (o) => o.supplierId == supplier && o.status == 'confirmed',
            );
        expect(open.length, 2);
        expect(open.every((o) => o.overlaps), isTrue);
        expect(await stock(a), before);
        // Reopen + full replay to a new terminal preserve snapshots and versions.
        await b.dispose();
        b = terminal('b');
        await b.tracking.pull(url).pullAvailableEvents();
        expect(
          (await b.tracking.orders.find(
            d1.orderId,
          ))!.document.toJson()['items'],
          d1.toJson()['items'],
        );
        final c = terminal('c');
        try {
          await c.tracking.pull(url).pullAvailableEvents();
          expect(
            (await c.tracking.orders.find(d2.orderId))!.status,
            'confirmed',
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
    skip: url == null ? 'Requiere POS_SUPPLIER_SYNC_URL aislado' : false,
  );
}
