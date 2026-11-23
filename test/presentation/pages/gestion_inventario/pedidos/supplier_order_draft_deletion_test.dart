import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_order_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_cancelled_payload.dart';
import 'package:pos_flutter/application/sync/projections/supplier_order_projection_store.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/domain/repositories/supplier_order_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_order_editor_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_orders_screen.dart';

import '../../../../application/commands/proveedores/supplier_order_local_test.dart'
    show seedOrders;
import '../../../../support/product_supplier_harness.dart';
import '../../../../support/supplier_order_harness.dart';

void main() {
  for (final mode in AppMode.values) {
    testWidgets(
      '${mode.name}: no elimina un pedido confirmado durante el diálogo',
      (tester) async {
        final h = ProductSupplierHarness(mode: mode);
        addTearDown(() async {
          await getIt.reset();
          await h.dispose();
        });
        await tester.runAsync(() => seedOrders(h));
        final doc = (await tester.runAsync(h.newOrder))!;
        await tester.runAsync(() async {
          await h.orders.save(await h.orderCommand(doc));
        });
        getIt.registerSingleton<SupplierOrderRepository>(
          DriftSupplierOrderRepository(h.db),
        );
        getIt.registerSingleton<SupplierOrderProjectionStore>(
          h.tracking.orders,
        );
        getIt.registerSingleton<SupplierOrderCommandService>(h.orders);
        await tester.pumpWidget(
          const MaterialApp(home: SupplierOrdersScreen()),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Borradores'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Eliminar borrador'));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await h.orders.save(
            await h.orderCommand(await h.based(doc.orderId), confirm: true),
          );
        });
        await tester.tap(
          find.widgetWithText(FilledButton, 'Eliminar borrador'),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('No se pudo eliminar el borrador:'),
          findsOneWidget,
        );
        expect(
          (await h.tracking.orders.find(doc.orderId))!.status,
          'confirmed',
        );
        final events = await h.db.select(h.db.events).get();
        expect(
          events.where(
            (e) => e.eventType == SupplierOrderCancelledPayload.eventType,
          ),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
    for (final editor in [false, true]) {
      testWidgets(
        '${mode.name}: eliminar borrador desde ${editor ? 'editor' : 'listado'}',
        (tester) async {
          final h = ProductSupplierHarness(mode: mode);
          addTearDown(() async {
            await getIt.reset();
            await h.dispose();
          });
          await tester.runAsync(() => seedOrders(h));
          final doc = (await tester.runAsync(h.newOrder))!;
          final other = (await tester.runAsync(h.newOrder))!;
          await tester.runAsync(() async {
            await h.orders.save(await h.orderCommand(doc));
            await h.orders.save(await h.orderCommand(other));
          });
          getIt.registerSingleton<SupplierOrderRepository>(
            DriftSupplierOrderRepository(h.db),
          );
          getIt.registerSingleton<SupplierOrderProjectionStore>(
            h.tracking.orders,
          );
          getIt.registerSingleton<SupplierOrderCommandService>(h.orders);
          await tester.pumpWidget(
            const MaterialApp(home: SupplierOrdersScreen()),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Borradores'));
          await tester.pumpAndSettle();
          if (editor) {
            await tester.tap(find.byKey(ValueKey(doc.orderId)));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('Eliminar borrador'));
            await tester.pumpAndSettle();
          }
          final action = editor
              ? find.text('Eliminar borrador')
              : find.descendant(
                  of: find.byKey(ValueKey(doc.orderId)),
                  matching: find.byTooltip('Eliminar borrador'),
                );
          await tester.tap(action);
          await tester.pumpAndSettle();
          expect(
            find.textContaining('se conservará como cancelado en Historial'),
            findsOneWidget,
          );
          await tester.tap(find.text('Volver'));
          await tester.pumpAndSettle();
          expect((await h.tracking.orders.find(doc.orderId))!.status, 'draft');
          await tester.tap(action);
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, 'Eliminar borrador'),
          );
          await tester.pumpAndSettle();
          expect(find.byType(SupplierOrderEditorScreen), findsNothing);
          expect(find.byKey(ValueKey(doc.orderId)), findsNothing);
          expect(find.byKey(ValueKey(other.orderId)), findsOneWidget);
          expect(
            (await h.tracking.orders.find(doc.orderId))!.status,
            'cancelled',
          );
          expect(
            (await h.tracking.orders.find(other.orderId))!.status,
            'draft',
          );
          final events = await h.db.select(h.db.events).get();
          final cancellation = events
              .where(
                (e) => e.eventType == SupplierOrderCancelledPayload.eventType,
              )
              .single;
          expect(cancellation.aggregateId, doc.orderId);
          expect(
            cancellation.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          final refs = await h.db.select(h.db.eventRefs).get();
          expect(
            refs.where((r) => r.eventId == cancellation.eventId),
            mode == AppMode.standalone ? isEmpty : isNotEmpty,
          );
          final candidates = await h.tracking.orders.candidates();
          expect(
            candidates
                .firstWhere((c) => c.supplierId == doc.supplierId)
                .balanceAtomic,
            3,
          );
          expect(
            candidates
                .firstWhere((c) => c.supplierId == doc.supplierId)
                .pendingAtomic,
            0,
          );
          await tester.ensureVisible(find.text('Historial'));
          await tester.tap(find.text('Historial'));
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey(doc.orderId)), findsOneWidget);
          expect(find.byTooltip('Eliminar borrador'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
}
