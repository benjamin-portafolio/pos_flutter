import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_order_command_service.dart';
import 'package:pos_flutter/application/commands/proveedores/recover_supplier_order_command.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import '../support/product_supplier_harness.dart';
import '../support/supplier_order_harness.dart';
import '../application/commands/proveedores/supplier_order_local_test.dart'
    show seedOrders;

void main() {
  final url = Platform.environment['POS_SUPPLIER_SYNC_URL'];
  test(
    'S3 rechazo HTTP real: undo inverso de cadena, reapertura y recuperación explícita con identidades nuevas',
    () async {
      final dir = await Directory.systemTemp.createTemp('orders-rejected-');
      final file = File('${dir.path}/db.sqlite');
      final context = LocalCommandContext(
        deviceId: const Uuid().v4(),
        userId: 'synthetic-rejection',
      );
      var h = ProductSupplierHarness(
        database: AppDatabase.forTesting(NativeDatabase(file)),
        mode: AppMode.serverSync,
        context: context,
      );
      Future<void> sync() async {
        for (var i = 0; i < 15; i++) {
          final pre = await h.tracking.preflight(url!).preflightPendingEvents();
          if (pre.requiresFullPullBeforePush) {
            await h.tracking.pull(url).pullAvailableEvents();
            continue;
          }
          final r = await h.tracking.push(url).pushPendingEvents();
          await h.tracking.pull(url).pullAvailableEvents();
          if (r.pending == 0) return;
        }
        fail('No converge');
      }

      Future<String> stock() async => jsonEncode([
        (await h.db.select(h.db.inventoryBalances).get())
            .map((r) => r.toJson())
            .toList(),
        (await h.db.select(h.db.inventoryMovements).get())
            .map((r) => r.toJson())
            .toList(),
      ]);
      try {
        final supplier = await seedOrders(h);
        await sync();
        final before = await stock();
        final document = await h.newOrder(supplierId: supplier);
        // Sobre deliberadamente rechazable; aceptación/rechazo y undo son reales.
        final invalid = SupplierOrderCommandService(
          store: h.tracking.orders,
          events: h.tracking.events,
          context: LocalCommandContext(deviceId: context.deviceId, userId: ' '),
          requireCompatible: () async {},
        );
        final draft = await h.orderCommand(document);
        await invalid.save(draft);
        final confirm = await h.orderCommand(
          await h.based(document.orderId),
          confirm: true,
        );
        await h.orders.save(confirm);
        final report = await h.tracking.push(url!).pushPendingEvents();
        expect(report.rejected, 1);
        expect(report.conflicts, 1);
        expect(await h.tracking.orders.find(document.orderId), isNull);
        expect(await stock(), before);
        expect(
          (await h.tracking.history.eventById(draft.eventId))!.deliveryStatus,
          'rejected',
        );
        expect(
          (await h.tracking.history.eventById(confirm.eventId))!.deliveryStatus,
          'conflict',
        );
        await h.dispose();
        h = ProductSupplierHarness(
          database: AppDatabase.forTesting(NativeDatabase(file)),
          mode: AppMode.serverSync,
          context: context,
        );
        final attempts = await DriftSupplierOrderRepository(
          h.db,
        ).watchFailedAttempts().first;
        expect(attempts.single.eventId, confirm.eventId);
        final recovered = const Uuid().v4();
        await h.orders.recover(
          RecoverSupplierOrderCommand(
            eventId: const Uuid().v4(),
            orderId: recovered,
            sourceEventId: confirm.eventId,
            itemIds: {for (final l in document.items) l.id: const Uuid().v4()},
            occurredAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        expect(
          (await h.tracking.orders.find(
            recovered,
          ))!.document.items.single.quantityAtomic,
          4,
        );
        await h.orders.save(
          await h.orderCommand(await h.based(recovered), confirm: true),
        );
        await sync();
        expect((await h.tracking.orders.find(recovered))!.status, 'confirmed');
        expect(await stock(), before);
      } finally {
        await h.dispose();
        await dir.delete(recursive: true);
      }
    },
    skip: url == null ? 'Requiere HTTP/PostgreSQL aislado' : false,
  );
}
