import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/repositories/supplier_order_repository.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/application/sync/projections/supplier_order_projection_store.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_order_command_service.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_orders_screen.dart';
import '../../../../support/product_supplier_harness.dart';
import '../../../../support/supplier_order_harness.dart';
import '../../../../application/commands/proveedores/supplier_order_local_test.dart'
    show seedOrders;

void main() {
  for (final width in [320.0, 1024.0]) {
    testWidgets(
      'S3 $width: preparar, editar, navegar, recuperar y confirmar sin acciones futuras',
      (tester) async {
        final h = ProductSupplierHarness();
        await tester.runAsync(() => seedOrders(h));
        getIt.registerSingleton<SupplierOrderRepository>(
          DriftSupplierOrderRepository(h.db),
        );
        getIt.registerSingleton<SupplierOrderProjectionStore>(
          h.tracking.orders,
        );
        getIt.registerSingleton<SupplierOrderCommandService>(h.orders);
        tester.view.reset();
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(() async {
          await getIt.reset();
          await h.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const SupplierOrdersScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Sugerido: 4 pza'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Preparar pedido'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Preparar pedido'));
        await tester.pumpAndSettle();
        final order = (await h.db.select(h.db.supplierOrders).get()).single;
        await tester.ensureVisible(find.widgetWithText(TextField, 'Notas'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Notas'),
          'Mi intención',
        );
        await tester.pump();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          (await h.tracking.orders.find(order.id))!.document.notes,
          'Mi intención',
        );
        await tester.pump();
        final search = find.widgetWithText(
          TextField,
          'Buscar proveedor o producto',
        );
        await tester.enterText(search, 'sin coincidencias');
        await tester.pumpAndSettle();
        expect((await h.tracking.orders.find(order.id))!.status, 'draft');
        await tester.enterText(search, '');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(ValueKey(order.id)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(order.id)));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, 'Café '));
        await tester.pumpAndSettle();
        final inputs = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(inputs.at(0), '2');
        await tester.enterText(inputs.at(1), '0');
        await tester.tap(find.text('Aplicar'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Revisar y confirmar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Revisar y confirmar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar pedido'));
        await tester.pumpAndSettle();
        expect((await h.tracking.orders.find(order.id))!.status, 'confirmed');
        final confirmed = (await h.tracking.orders.find(order.id))!;
        expect(confirmed.document.items.single.quantityAtomic, 2);
        expect(confirmed.document.totalMinor, 0);
        expect(find.text('Recibir'), findsNothing);
        expect(find.text('Imprimir'), findsNothing);
        expect(find.text('Compartir'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
