import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/repositories/supplier_order_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_orders_screen.dart';

import '../../../../application/commands/proveedores/supplier_order_local_test.dart'
    show seedOrders;
import '../../../../support/product_supplier_harness.dart';

void main() {
  for (final fromSupplier in [false, true]) {
    testWidgets(
      'Corregir abre la variante desde ${fromSupplier ? 'Proveedores' : 'Inventario'} y permite volver sin cambios',
      (tester) async {
        final h = ProductSupplierHarness();
        final supplier = await tester.runAsync(() => seedOrders(h));
        final variant = (await h.db.select(h.db.productVariants).get()).single;
        await h.db
            .update(h.db.productVariants)
            .write(
              const ProductVariantsCompanion(currentSupplierId: Value(null)),
            );
        final eventsBefore = (await h.db.select(h.db.events).get()).length;
        getIt.registerSingleton<SupplierOrderRepository>(
          DriftSupplierOrderRepository(h.db),
        );
        addTearDown(() async {
          await getIt.reset();
          await h.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: InventoryManagementScreen(
              productoRepository: h.repository,
              productoCommandService: h.commands,
              categoriaRepository: CategoriaRepositoryImpl(
                categoriaDao: h.db.categoriaDao,
              ),
              appConfigController: h.tracking.config,
              proveedorRepository: ProveedorRepositoryImpl(h.db.proveedorDao),
              recursoInventarioRepository: RecursoInventarioRepositoryImpl(
                inventoryDao: h.db.inventoryDao,
              ),
              unidadInventarioRepository: UnidadInventarioRepositoryImpl(
                unitDao: h.db.unitDao,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (fromSupplier) {
          await tester.tap(find.text('PROVEEDORES'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(Key('supplier_$supplier')));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Preparar pedido / Ver pedidos'));
        } else {
          await tester.tap(find.byTooltip('Pedidos a proveedores'));
        }
        await tester.pumpAndSettle();
        expect(find.text('Falta proveedor actual'), findsNothing);
        await tester.tap(
          find.byKey(const PageStorageKey('supplier_configuration_issues')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Falta proveedor actual'), findsOneWidget);
        await tester.ensureVisible(find.text('Corregir'));
        await tester.tap(find.text('Corregir'));
        await tester.pumpAndSettle();
        expect(find.byType(ArticleFormScreen), findsOneWidget);
        final form = tester.widget<ArticleFormScreen>(
          find.byType(ArticleFormScreen),
        );
        expect(form.initialVariantId, variant.id);
        expect(form.preview, isFalse);
        final card = find.byKey(const Key('article_variant_card_0'));
        await tester.ensureVisible(card);
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(find.byType(VariantEditorScreen), findsOneWidget);
        expect(
          tester
              .widget<VariantEditorScreen>(find.byType(VariantEditorScreen))
              .preview,
          isFalse,
        );
        await tester.tap(find.byKey(const Key('close_variant_editor_button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Cancelar'));
        await tester.pumpAndSettle();
        expect(find.byType(SupplierOrdersScreen), findsOneWidget);
        expect(find.text('Falta proveedor actual'), findsOneWidget);
        expect((await h.db.select(h.db.events).get()).length, eventsBefore);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
