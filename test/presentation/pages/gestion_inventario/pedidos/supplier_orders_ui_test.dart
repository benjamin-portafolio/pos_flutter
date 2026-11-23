import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/domain/repositories/supplier_order_repository.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/application/sync/projections/supplier_order_projection_store.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_order_command_service.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_orders_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_order_variant_search_screen.dart';
import '../../../../support/product_supplier_harness.dart';
import '../../../../support/supplier_order_harness.dart';
import '../../../../application/commands/proveedores/supplier_order_local_test.dart'
    show seedOrders;

void main() {
  for (final width in [320.0, 1024.0]) {
    for (final measured in [false, true]) {
      testWidgets(
        'S3 $width medido=$measured: preparar, editar, navegar, recuperar y confirmar sin acciones futuras',
        (tester) async {
          final h = ProductSupplierHarness();
          await tester.runAsync(() => seedOrders(h, measured: measured));
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
          expect(find.text('1 producto · 1 por reponer'), findsOneWidget);
          expect(find.textContaining('Sugerido:'), findsNothing);
          await tester.tap(find.byType(ExpansionTile).first);
          await tester.pumpAndSettle();
          expect(
            find.textContaining(
              measured ? 'Sugerido: 4 kg' : 'Sugerido: 4 pza',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Borradores'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Borradores'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'No tienes borradores guardados. Prepara un pedido desde Sugerencias.',
            ),
            findsOneWidget,
          );
          expect(find.text('Preparar pedido'), findsNothing);
          await tester.ensureVisible(find.text('Sugerencias'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Sugerencias'));
          await tester.pumpAndSettle();
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
          expect(
            find.text('No hay sugerencias para esta búsqueda.'),
            findsOneWidget,
          );
          await tester.enterText(search, '');
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey(order.id)), findsNothing);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('supplier_orders_tab_draft')),
              matching: find.text('1'),
            ),
            findsOneWidget,
          );
          await tester.ensureVisible(find.text('Borradores'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Borradores'));
          await tester.pumpAndSettle();
          await tester.enterText(search, 'sin coincidencias');
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey(order.id)), findsNothing);
          expect(
            find.text('No hay pedidos para esta búsqueda.'),
            findsOneWidget,
          );
          await tester.enterText(search, '');
          await tester.pumpAndSettle();
          final summary = find.descendant(
            of: find.byKey(ValueKey(order.id)),
            matching: find.byType(Text),
          );
          expect(
            summary.evaluate().map((e) => (e.widget as Text).data).join(' '),
            allOf(
              contains('Guardado el '),
              contains('Total estimado: '),
              isNot(contains(order.id)),
              isNot(contains('not_required')),
            ),
          );
          await tester.ensureVisible(find.byKey(ValueKey(order.id)));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ValueKey(order.id)));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byTooltip('Editar artículo'));
          await tester.tap(find.byTooltip('Editar artículo'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Aumentar cantidad'));
          await tester.pumpAndSettle();
          expect(find.text(measured ? '4.001' : '5'), findsOneWidget);
          await tester.tap(find.byTooltip('Disminuir cantidad'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('order_quantity_field')),
            '0',
          );
          await tester.tap(find.text('Listo'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('order_quantity_field')), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('order_quantity_field')),
            '9',
          );
          await tester.tap(find.text('Cancelar edición'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Editar artículo'));
          await tester.pumpAndSettle();
          expect(find.text('4'), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('order_quantity_field')),
            measured ? '2.5' : '2',
          );
          await tester.tap(find.text('Listo'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Eliminar artículo'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'El pedido está vacío. Agrega un producto para continuar.',
            ),
            findsOneWidget,
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Revisar y confirmar'),
                )
                .onPressed,
            isNull,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Salir sin guardar cambios'), findsOneWidget);
          await tester.tap(find.text('Volver'));
          await tester.pumpAndSettle();
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Salir sin guardar'));
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey(order.id)), findsOneWidget);
          expect(
            (await h.tracking.orders.find(
              order.id,
            ))!.document.items.single.quantityAtomic,
            measured ? 4000 : 4,
          );
          await tester.ensureVisible(find.byKey(ValueKey(order.id)));
          await tester.tap(find.byKey(ValueKey(order.id)));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Agregar variante'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Agregar variante'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'No hay variantes disponibles para agregar de este proveedor.',
            ),
            findsOneWidget,
          );
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Café'), findsOneWidget);
          await tester.ensureVisible(find.byTooltip('Eliminar artículo'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Eliminar artículo'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Agregar variante'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Agregar variante'));
          await tester.pumpAndSettle();
          expect(find.byType(SupplierOrderVariantSearchScreen), findsOneWidget);
          await tester.enterText(
            find.widgetWithText(TextField, 'Buscar producto o variante'),
            '  CAFÉ  ',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, 'Café'));
          await tester.pumpAndSettle();
          // Restar la última unidad elimina la partida, como en Caja.
          await tester.tap(find.byTooltip('Editar artículo'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Disminuir cantidad'));
          await tester.pumpAndSettle();
          if (!measured) {
            expect(
              find.text(
                'El pedido está vacío. Agrega un producto para continuar.',
              ),
              findsOneWidget,
            );
            await tester.ensureVisible(find.text('Agregar variante'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Agregar variante'));
            await tester.pumpAndSettle();
            expect(
              find.byType(SupplierOrderVariantSearchScreen),
              findsOneWidget,
            );
            await tester.enterText(
              find.widgetWithText(TextField, 'Buscar producto o variante'),
              '  CAFÉ  ',
            );
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(ListTile, 'Café'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Editar artículo'));
            await tester.pumpAndSettle();
          }
          await tester.enterText(
            find.byKey(const Key('order_quantity_field')),
            measured ? '2.5' : '2',
          );
          await tester.tap(find.text('Listo'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Editar precio'));
          await tester.tap(find.text('Editar precio'));
          await tester.pumpAndSettle();
          final input = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );
          await tester.enterText(input, '');
          await tester.tap(find.text('Aplicar'));
          await tester.pumpAndSettle();
          expect(
            find.text('Estimado incompleto: hay productos sin precio.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Editar precio'));
          await tester.pumpAndSettle();
          await tester.enterText(input, '0');
          await tester.tap(find.text('Aplicar'));
          await tester.pumpAndSettle();
          expect(
            find.text('Estimado incompleto: hay productos sin precio.'),
            findsNothing,
          );
          await tester.ensureVisible(find.text('Revisar y confirmar'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Revisar y confirmar'));
          await tester.pumpAndSettle();
          expect(find.textContaining('átomos'), findsNothing);
          expect(
            find.textContaining(
              measured ? 'Existencias: 3 kg' : 'Existencias: 3 pza',
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Confirmar pedido'));
          await tester.pumpAndSettle();
          expect((await h.tracking.orders.find(order.id))!.status, 'confirmed');
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('supplier_orders_tab_draft')),
              matching: find.text('0'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('supplier_orders_tab_confirmed')),
              matching: find.text('1'),
            ),
            findsOneWidget,
          );
          final confirmed = (await h.tracking.orders.find(order.id))!;
          expect(
            confirmed.document.items.single.quantityAtomic,
            measured ? 2500 : 2,
          );
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
}
