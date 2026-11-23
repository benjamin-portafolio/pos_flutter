import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_orders_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_order_detail_screen.dart';

import '../support/product_supplier_harness.dart';
import '../support/supplier_order_harness.dart';
import '../application/commands/proveedores/supplier_order_local_test.dart'
    show seedOrders;
import '../application/commands/proveedores/supplier_receipt_local_test.dart'
    show receipt;
import '../presentation/pages/gestion_inventario/pedidos/supplier_receipts_ui_test.dart'
    show register, tap;

void main() {
  final url = Platform.environment['POS_SUPPLIER_SYNC_URL'];
  testWidgets(
    'S6 UI + HTTP/PG: preparar/reabrir/confirmar, recepción concurrente, conflicto visible y nueva intención',
    (t) async {
      final previousHttp = HttpOverrides.current;
      HttpOverrides.global = null;
      final dir = Directory.systemTemp.createTempSync('supplier-public-http-');
      final run = const Uuid().v4();
      ProductSupplierHarness terminal(String id) => ProductSupplierHarness(
        mode: AppMode.serverSync,
        context: LocalCommandContext(
          deviceId: 's6-$run-$id',
          userId: 'synthetic',
        ),
        database: AppDatabase.forTesting(
          NativeDatabase(File('${dir.path}/$id.sqlite')),
        ),
      );
      final a = terminal('a'), b = terminal('b');
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

      addTearDown(() async {
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        await getIt.reset();
        await t.runAsync(() async {
          await a.dispose();
          await b.dispose();
          await dir.delete(recursive: true);
        });
        HttpOverrides.global = previousHttp;
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      late String supplier;
      await t.runAsync(() async {
        supplier = await seedOrders(a);
        await sync(a);
        await b.tracking.pull(url!).pullAvailableEvents();
      });
      register(a);
      t.view.physicalSize = const Size(1024, 1100);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        MaterialApp(home: SupplierOrdersScreen(supplierId: supplier)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(PageStorageKey('supplier_suggestions_$supplier')));
      await t.pumpAndSettle();
      await tap(t, 'Preparar pedido');
      await t.ensureVisible(find.widgetWithText(TextField, 'Notas'));
      await t.enterText(
        find.widgetWithText(TextField, 'Notas'),
        'Recorrido público HTTP S6',
      );
      await t.pump();
      await tap(t, 'Guardar pedido');
      final id = (await a.db.select(a.db.supplierOrders).get())
          .singleWhere((o) => o.supplierId == supplier && o.status == 'draft')
          .id;
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(t, 'Borradores');
      await t.ensureVisible(find.byKey(ValueKey(id)));
      await t.tap(find.byKey(ValueKey(id)));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.widgetWithText(TextField, 'Notas'))
            .controller!
            .text,
        'Recorrido público HTTP S6',
      );
      await tap(t, 'Revisar y confirmar');
      await tap(t, 'Confirmar pedido');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await sync(a);
        await b.tracking.pull(url!).pullAvailableEvents();
      });
      await t.pumpAndSettle();
      // Both clients capture against the same accepted order head.
      final competing = (await t.runAsync(() => receipt(b, id, 3)))!;
      await t.pumpWidget(
        MaterialApp(home: SupplierOrderDetailScreen(orderId: id)),
      );
      await t.pumpAndSettle();
      await tap(t, 'Recibir mercancía');
      await t.enterText(find.byType(TextField).at(0), '3');
      await tap(t, 'Revisar recepción');
      await tap(t, 'Confirmar entrada de inventario');
      await tap(t, 'Volver al detalle');
      final losingReceipt = (await a.db.select(a.db.supplierReceipts).get())
          .singleWhere((r) => r.orderId == id)
          .id;
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await b.orders.receive(competing);
        await sync(b);
        final report = await a.tracking.push(url!).pushPendingEvents();
        expect(report.conflicts, 1);
        await a.tracking.pull(url).pullAvailableEvents();
      });
      await t.pumpAndSettle();
      await t.pumpWidget(
        MaterialApp(home: SupplierOrderDetailScreen(orderId: id)),
      );
      await t.pumpAndSettle();
      final revise = 'Revisar intención rechazada $losingReceipt';
      expect(find.text(revise), findsOneWidget);
      expect(
        (await a.db.select(a.db.supplierReceipts).get())
            .where((r) => r.orderId == id)
            .length,
        1,
      );
      await tap(t, revise);
      await t.enterText(find.byType(TextField).at(0), '1');
      await tap(t, 'Revisar recepción');
      await tap(t, 'Confirmar entrada de inventario');
      await tap(t, 'Volver al detalle');
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await sync(a);
        await b.tracking.pull(url!).pullAvailableEvents();
      });
      await t.pumpAndSettle();
      expect((await a.tracking.orders.find(id))!.status, 'received');
      final item = (await a.tracking.orders.find(
        id,
      ))!.document.items.single.inventoryItemId;
      for (final h in [a, b]) {
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .singleWhere((r) => r.inventoryItemId == item)
              .quantityOnHandAtomic,
          7,
        );
        expect(
          (await h.db.select(h.db.supplierReceipts).get())
              .where((r) => r.orderId == id)
              .length,
          2,
        );
        expect(
          (await h.tracking.orders.candidates())
              .firstWhere((r) => r.inventoryItemId == item && r.isCurrent)
              .pendingAtomic,
          0,
        );
      }
      expect(t.takeException(), isNull);
    },
    skip: url == null,
  );
}
