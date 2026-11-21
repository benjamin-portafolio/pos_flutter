import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/domain/repositories/supplier_order_repository.dart';
import 'package:pos_flutter/application/sync/projections/supplier_order_projection_store.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_order_command_service.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_orders_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/remaining_stock_screen.dart';
import '../../../../support/product_supplier_harness.dart';
import '../../../../support/supplier_order_harness.dart';
import '../../../../application/commands/proveedores/supplier_order_local_test.dart'
    show seedOrders;

void main() {
  testWidgets(
    'S3 accesos públicos: Inventario, proveedor e informe abren el mismo módulo',
    (tester) async {
      final h = ProductSupplierHarness();
      final supplier = await tester.runAsync(() => seedOrders(h));
      getIt.registerSingleton<SupplierOrderRepository>(
        DriftSupplierOrderRepository(h.db),
      );
      getIt.registerSingleton<SupplierOrderProjectionStore>(h.tracking.orders);
      getIt.registerSingleton<SupplierOrderCommandService>(h.orders);
      addTearDown(() async {
        await getIt.reset();
        await h.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryManagementScreen(
            productoRepository: h.repository,
            categoriaRepository: CategoriaRepositoryImpl(
              categoriaDao: h.db.categoriaDao,
            ),
            appConfigController: h.tracking.config,
            proveedorRepository: ProveedorRepositoryImpl(h.db.proveedorDao),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pedidos a proveedores'));
      await tester.pumpAndSettle();
      expect(find.byType(SupplierOrdersScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('PROVEEDORES'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('supplier_$supplier')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Preparar pedido / Ver pedidos'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SupplierOrdersScreen>(find.byType(SupplierOrdersScreen))
            .supplierId,
        supplier,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(home: RemainingStockScreen(repository: h.repository)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Crear pedido'));
      await tester.pumpAndSettle();
      expect(find.byType(SupplierOrdersScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
