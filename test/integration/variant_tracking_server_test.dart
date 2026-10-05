import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import '../support/variant_tracking_harness.dart';

/// Requires the isolated Nest HTTP harness in pos-nest/test/support.
/// Explicitly skipped without a URL; this is never presented as a physical UI run.
void main() {
  final url = Platform.environment['POS_PHASE3_SYNC_URL'];
  test(
    'HTTP real: B cobra offline, A desvincula, B entrega, duplicado y pull desde cero',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final run = const Uuid().v4();
      VariantTrackingHarness terminal(String letter) => VariantTrackingHarness(
        mode: AppMode.serverSync,
        context: LocalCommandContext(
          deviceId: '$run-$letter',
          userId: 'phase3-test',
        ),
      );
      final a = terminal('A'), b = terminal('B'), c = terminal('C');
      addTearDown(() async {
        for (final h in [a, b, c]) {
          await h.config.dispose();
          await h.db.close();
        }
      });
      final ids = await a.create(initial: '10');
      Future<void> pushAll(VariantTrackingHarness h) async {
        for (
          var i = 0;
          i < 6 && (await h.history.pendingEvents()).isNotEmpty;
          i++
        ) {
          final report = await h.push(url!).pushPendingEvents();
          expect(report.rejected, 0);
          expect(report.conflicts, 0);
        }
        expect(await h.history.pendingEvents(), isEmpty);
      }

      await pushAll(a);
      await a.pull(url!).pullAvailableEvents();
      await b.pull(url).pullAvailableEvents();
      await b.drafts.agregar(
        AgregarProductoBorradorCommand(variantId: ids.variantId),
      );
      final draft = (await b.db.select(b.db.sales).get()).singleWhere(
        (s) => s.deviceId == b.context.deviceId,
      );
      await b.sales.confirmar(
        ConfirmarVentaCommand(
          saleId: draft.id,
          expectedDraftEventId: draft.lastEventId!,
          expectedTotalMinor: draft.totalMinor,
          paymentMethod: 'transfer',
        ),
      );
      final sale = (await b.storedEvents()).singleWhere(
        (e) =>
            e.eventType == VentaConfirmadaPayload.eventType &&
            e.deviceId == b.context.deviceId,
      );
      final payload = VentaConfirmadaPayload.fromJson(sale.payload);
      expect(
        payload.lines.single.consumptions.single.inventoryItemId,
        ids.resourceId,
      );
      expect(
        (await b.tracking.balanceOf(ids.resourceId!))!.quantityOnHandAtomic,
        9,
      );
      await b.save(ids.productId, ids.variantId);
      final bOff = (await b.storedEvents()).last;
      await b.save(
        ids.productId,
        ids.variantId,
        tracked: true,
        name: 'Cambio local B',
      );
      final bOn = (await b.storedEvents()).last;
      final off = await a.save(ids.productId, ids.variantId);
      expect(off.discardedInventoryItemIds, isEmpty);
      await pushAll(a);
      await a.pull(url).pullAvailableEvents();
      // B has received no network input since it captured and charged the sale.
      final bReport = await b.push(url).pushPendingEvents();
      expect(bReport.synced, 1);
      expect(bReport.conflicts, 2);
      expect(bReport.rejected, 0);
      expect(await b.history.pendingEvents(), isEmpty);
      expect(
        (await b.history.eventById(bOff.eventId))!.deliveryStatus,
        'conflict',
      );
      expect(
        (await b.history.eventById(bOn.eventId))!.deliveryStatus,
        'conflict',
      );
      expect(
        (await b.products.snapshot(
          ids.productId,
        )).variantes.single.inventoryItemId,
        ids.resourceId,
      );
      expect(
        (await b.tracking.balanceOf(ids.resourceId!))!.quantityOnHandAtomic,
        9,
      );
      expect(
        (await b.db.select(b.db.sales).get()).where(
          (s) => s.id == sale.aggregateId,
        ),
        hasLength(1),
      );
      expect(await b.db.select(b.db.productUpdateUndo).get(), isEmpty);
      await b.pull(url).pullAvailableEvents();
      final duplicate = await http.post(
        Uri.parse('$url/sync/push'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': b.context.deviceId,
          'events': [sale.toPushJson()],
        }),
      );
      expect(duplicate.statusCode, 201);
      expect(
        (jsonDecode(duplicate.body) as Map)['results'][0]['status'],
        'duplicate',
      );
      await a.pull(url).pullAvailableEvents();
      expect(
        (await a.tracking.balanceOf(ids.resourceId!))!.quantityOnHandAtomic,
        9,
      );
      expect(
        (await a.products.snapshot(
          ids.productId,
        )).variantes.single.inventoryItemId,
        isNull,
      );
      final resourcesBefore =
          (await a.db.select(a.db.inventoryItems).get()).length;
      final movementsBefore =
          (await a.db.select(a.db.inventoryMovements).get()).length;
      await a.save(ids.productId, ids.variantId, tracked: true);
      expect(
        (await a.products.snapshot(
          ids.productId,
        )).variantes.single.inventoryItemId,
        ids.resourceId,
      );
      expect(
        (await a.db.select(a.db.inventoryItems).get()).length,
        resourcesBefore,
      );
      expect(
        (await a.db.select(a.db.inventoryMovements).get()).length,
        movementsBefore,
      );
      final preflight = await a.preflight(url).preflightPendingEvents();
      expect(preflight.skipped, false);
      expect(preflight.localConflicts, 0);
      expect(preflight.requiresFullPullBeforePush, false);
      await pushAll(a);
      await c.pull(url).pullAvailableEvents();
      expect(
        (await c.products.snapshot(
          ids.productId,
        )).variantes.single.inventoryItemId,
        ids.resourceId,
      );
      expect(
        (await c.memory.findByVariantId(ids.variantId))!.inventoryItemId,
        ids.resourceId,
      );
      expect(
        (await c.tracking.balanceOf(ids.resourceId!))!.quantityOnHandAtomic,
        9,
      );
      expect(
        (await c.db.select(c.db.sales).get()).where(
          (s) => s.id == sale.aggregateId,
        ),
        hasLength(1),
      );
      expect(
        (await c.db.select(c.db.salePayments).get()).where(
          (p) => p.saleId == sale.aggregateId,
        ),
        hasLength(1),
      );
      expect(
        (await c.db.select(c.db.inventoryMovements).get()).where(
          (m) => m.inventoryItemId == ids.resourceId,
        ),
        hasLength(2),
      );
      final repeatedPull = await c.pull(url).pullAvailableEvents();
      expect(repeatedPull.total, 0);
      expect(
        (await c.tracking.balanceOf(ids.resourceId!))!.quantityOnHandAtomic,
        9,
      );
      final evidence = Platform.environment['POS_PHASE3_CLIENT_EVIDENCE'];
      if (evidence != null) {
        await File(evidence).writeAsString(
          jsonEncode({
            'product_id': ids.productId,
            'variant_id': ids.variantId,
            'resource_id': ids.resourceId,
            'sale_id': sale.aggregateId,
            'sale_event_id': sale.eventId,
            'quantity': 9,
            'movements': 2,
            'sales': 1,
            'payments': 1,
            'pull_cursor': await c.history.lastFullPullServerSequence(),
          }),
        );
      }
    },
    skip: url == null
        ? 'Requires POS_PHASE3_SYNC_URL pointing to an isolated PostgreSQL-backed Nest test server.'
        : false,
  );
}
