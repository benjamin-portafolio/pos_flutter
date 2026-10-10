import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';

import '../../../../support/product_supplier_harness.dart';

void main() {
  late ProductSupplierHarness h;
  late Directory temp;
  late String supplierId;
  late String otherId;
  late String productId;
  late HttpOverrides? previousHttpOverrides;
  late _NoNetwork network;
  const oldDate = 1791331200123;

  setUp(() async {
    previousHttpOverrides = HttpOverrides.current;
    network = _NoNetwork();
    HttpOverrides.global = network;
    temp = await Directory.systemTemp.createTemp('supplier-ui-');
    h = ProductSupplierHarness(
      database: AppDatabase.forTesting(
        NativeDatabase(File('${temp.path}/pos.sqlite')),
      ),
    );
    supplierId = await h.supplier('Distribuidora Norte');
    otherId = await h.supplier('Proveedor Sur');
    await h.commands.crearArticulo(
      CrearArticuloCommand.conVariantes(
        nombre: 'Café',
        variantes: [
          CrearArticuloVarianteCommand.conProveedores(
            nombre: 'Bolsa',
            precioVenta: '25',
            costoEstandar: '10',
            proveedores: [
              ProveedorVariante(
                proveedorId: supplierId,
                precioInformadoMenor: 1234,
                fechaInformadaMs: oldDate,
              ),
            ],
          ),
        ],
      ),
    );
    productId = h.appends.last.event.aggregateId;
  });
  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    expect(network.clients, 0);
    await h.dispose();
    await temp.delete(recursive: true);
  });

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, String key) async {
    await tester.pump();
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  Future<void> inventory(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InventoryManagementScreen(
          categoriaRepository: CategoriaRepositoryImpl(
            categoriaDao: h.db.categoriaDao,
          ),
          productoRepository: h.repository,
          productoCommandService: h.commands,
          proveedorRepository: ProveedorRepositoryImpl(h.db.proveedorDao),
          proveedorCommandService: h.supplierCommands,
          appConfigController: h.tracking.config,
          unidadInventarioRepository: UnidadInventarioRepositoryImpl(
            unitDao: h.db.unitDao,
          ),
          recursoInventarioRepository: RecursoInventarioRepositoryImpl(
            inventoryDao: h.db.inventoryDao,
          ),
        ),
      ),
    );
    await flush(tester);
  }

  Future<void> article(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Café Bolsa'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(ArticleFormScreen), findsOneWidget);
  }

  Future<void> variant(WidgetTester tester) async {
    await click(tester, 'article_variant_card_0');
    expect(find.byType(VariantEditorScreen), findsOneWidget);
  }

  Future<void> selector(WidgetTester tester) async {
    await click(tester, 'manage_variant_suppliers_button');
    await flush(tester);
    expect(
      find.byKey(const Key('variant_suppliers_editor_screen')),
      findsOneWidget,
    );
  }

  Future<List<ProveedorVariante>> relations(WidgetTester tester) async =>
      (await tester.runAsync(
        () async => (await h.repository.obtenerDetalle(
          productId,
        ))!.variantes.single.proveedores!,
      ))!;
  Future<int> eventCount(WidgetTester tester) async => (await tester.runAsync(
    () async => (await h.db.select(h.db.events).get()).length,
  ))!;
  Future<void> cleanup(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }

  for (final level in ['selector', 'variante', 'artículo']) {
    testWidgets('cancelar $level conserva relaciones y eventos SQLite', (
      tester,
    ) async {
      try {
        await inventory(tester);
        final before = await relations(tester);
        final count = await eventCount(tester);
        await article(tester);
        await variant(tester);
        await selector(tester);
        await tester.enterText(
          find.byKey(Key('supplier_price_$supplierId')),
          '30',
        );
        if (level == 'selector') {
          await click(tester, 'close_variant_suppliers_button');
          await click(tester, 'save_variant_button');
          expect(find.byKey(const Key('save_article_button')), findsNothing);
        } else {
          await click(tester, 'save_variant_suppliers_button');
          expect(await relations(tester), before);
          expect(await eventCount(tester), count);
          if (level == 'variante') {
            await click(tester, 'close_variant_editor_button');
            expect(find.byKey(const Key('save_article_button')), findsNothing);
          } else {
            await click(tester, 'save_variant_button');
            expect(
              find.byKey(const Key('save_article_button')),
              findsOneWidget,
            );
            await tester.tap(find.byTooltip('Cancelar'));
            await tester.pumpAndSettle();
            await click(tester, 'discard_article_changes_button');
            expect(find.byType(ArticleFormScreen), findsNothing);
          }
        }
        expect(await relations(tester), before);
        expect(await eventCount(tester), count);
      } finally {
        await cleanup(tester);
      }
    });
  }

  testWidgets(
    'seleccionar, guardar, reabrir, cambiar precio y retirar último desde UI',
    (tester) async {
      try {
        await inventory(tester);
        final initial = await relations(tester);
        final count = await eventCount(tester);
        await article(tester);
        await variant(tester);
        await selector(tester);
        await click(tester, 'select_variant_supplier_$otherId');
        await tester.enterText(
          find.byKey(Key('supplier_price_$otherId')),
          '0,00',
        );
        await click(tester, 'save_variant_suppliers_button');
        expect(await relations(tester), initial);
        await click(tester, 'save_variant_button');
        expect(await relations(tester), initial);
        await click(tester, 'save_article_button');
        await flush(tester);
        final saved = await relations(tester);
        expect(saved, hasLength(2));
        expect(
          saved.singleWhere((r) => r.proveedorId == supplierId),
          initial.single,
        );
        expect(
          saved
              .singleWhere((r) => r.proveedorId == otherId)
              .precioInformadoMenor,
          0,
        );
        expect(await eventCount(tester), count + 1);
        await cleanup(tester);
        await tester.runAsync(() async {
          await h.dispose();
          h = ProductSupplierHarness(
            database: AppDatabase.forTesting(
              NativeDatabase(File('${temp.path}/pos.sqlite')),
            ),
          );
        });
        await inventory(tester);
        expect(await relations(tester), saved);
        await article(tester);
        await variant(tester);
        await selector(tester);
        expect(
          tester
              .widget<TextField>(find.byKey(Key('supplier_price_$otherId')))
              .controller!
              .text,
          '0.00',
        );
        await tester.enterText(
          find.byKey(Key('supplier_price_$supplierId')),
          '15.50',
        );
        await click(tester, 'select_variant_supplier_$otherId');
        await click(tester, 'save_variant_suppliers_button');
        await click(tester, 'save_variant_button');
        await click(tester, 'save_article_button');
        await flush(tester);
        expect((await relations(tester)).single.precioInformadoMenor, 1550);
        await article(tester);
        await variant(tester);
        await selector(tester);
        await click(tester, 'select_variant_supplier_$supplierId');
        await click(tester, 'save_variant_suppliers_button');
        await click(tester, 'save_variant_button');
        await click(tester, 'save_article_button');
        await flush(tester);
        expect(await relations(tester), isEmpty);
        final providers = await tester.runAsync(
          () => ProveedorRepositoryImpl(
            h.db.proveedorDao,
          ).watchProveedores().first,
        );
        expect(providers, hasLength(2));
        final data = await tester.runAsync(
          () => h.repository.obtenerDetalle(productId),
        );
        expect(data!.variantes.single.precioVentaMenor, 2500);
        expect(data.variantes.single.costoEstandarMenor, 1000);
        final refs = await tester.runAsync(
          () => h.db.select(h.db.eventRefs).get(),
        );
        expect(refs, isEmpty);
        final events = await tester.runAsync(
          () => h.db.select(h.db.events).get(),
        );
        expect(
          events!.every(
            (e) =>
                e.deliveryStatus == 'not_required' &&
                e.applicationStatus == 'applied',
          ),
          isTrue,
        );
        await cleanup(tester);
        await tester.runAsync(() async {
          await h.dispose();
          h = ProductSupplierHarness(
            database: AppDatabase.forTesting(
              NativeDatabase(File('${temp.path}/pos.sqlite')),
            ),
          );
        });
        await inventory(tester);
        await article(tester);
        await variant(tester);
        await selector(tester);
        expect(find.byType(TextField), findsNothing);
        expect(await relations(tester), isEmpty);
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets(
    'fallo atómico al guardar conserva borrador y reintento persiste una vez',
    (tester) async {
      try {
        await inventory(tester);
        final initial = await relations(tester);
        final count = await eventCount(tester);
        await article(tester);
        await variant(tester);
        await selector(tester);
        await tester.enterText(
          find.byKey(Key('supplier_price_$supplierId')),
          '18,75',
        );
        await click(tester, 'save_variant_suppliers_button');
        await click(tester, 'save_variant_button');
        h.failAfterProductApply = true;
        await click(tester, 'save_article_button');
        expect(find.byKey(const Key('article_save_error')), findsOneWidget);
        expect(await relations(tester), initial);
        expect(await eventCount(tester), count);
        await variant(tester);
        await selector(tester);
        expect(
          tester
              .widget<TextField>(find.byKey(Key('supplier_price_$supplierId')))
              .controller!
              .text,
          '18.75',
        );
        await click(tester, 'close_variant_suppliers_button');
        await click(tester, 'close_variant_editor_button');
        h.failAfterProductApply = false;
        await click(tester, 'save_article_button');
        await flush(tester);
        expect((await relations(tester)).single.precioInformadoMenor, 1875);
        expect(await eventCount(tester), count + 1);
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets(
    'alta de artículo desde menú guarda proveedores solo al finalizar',
    (tester) async {
      try {
        await inventory(tester);
        final count = await eventCount(tester);
        await tester.tap(find.byTooltip('Agregar'));
        await tester.pumpAndSettle();
        await click(tester, 'add_article_option');
        await tester.enterText(
          find.byKey(const Key('article_name_field')),
          'Artículo nuevo',
        );
        await tester.ensureVisible(find.text('Avanzado'));
        await tester.tap(find.text('Avanzado'));
        await tester.pumpAndSettle();
        await click(tester, 'add_article_variant_button');
        await tester.enterText(
          find.byKey(const Key('variant_name_field')),
          'Caja',
        );
        await tester.enterText(
          find.byKey(const Key('variant_sale_price_field')),
          '40',
        );
        await selector(tester);
        await click(tester, 'select_variant_supplier_$supplierId');
        await tester.enterText(
          find.byKey(Key('supplier_price_$supplierId')),
          '20,25',
        );
        await click(tester, 'save_variant_suppliers_button');
        await click(tester, 'save_variant_button');
        expect(await eventCount(tester), count);
        await click(tester, 'save_article_button');
        await flush(tester);
        expect(await eventCount(tester), count + 1);
        productId = h.appends
            .lastWhere(
              (a) => a.event.eventType == ProductoCreadoPayload.eventType,
            )
            .event
            .aggregateId;
        expect((await relations(tester)).single.precioInformadoMenor, 2025);
        await tester.runAsync(() async {
          await tester.tap(find.text('Artículo nuevo Caja'));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        await variant(tester);
        await selector(tester);
        expect(
          tester
              .widget<TextField>(find.byKey(Key('supplier_price_$supplierId')))
              .controller!
              .text,
          '20.25',
        );
      } finally {
        await cleanup(tester);
      }
    },
  );

  testWidgets(
    'edición medida muestra y conserva referencia original al guardar precios',
    (tester) async {
      try {
        await tester.runAsync(() async {
          await h.commands.crearArticulo(
            CrearArticuloCommand.conVariantes(
              nombre: 'Café medido',
              saleConfiguration: MeasuredSaleConfiguration(
                saleUnitId: InventoryUnitIds.kilogram,
                priceReferenceQuantityAtomic: 1000,
              ),
              variantes: [
                CrearArticuloVarianteCommand.conProveedores(
                  nombre: 'Bolsa',
                  precioVenta: '25',
                  costoEstandar: null,
                  proveedores: [],
                ),
              ],
            ),
          );
          productId = h.appends.last.event.aggregateId;
        });
        final detail = await tester.runAsync(
          () => h.repository.obtenerDetalle(productId),
        );
        await inventory(tester);
        await tester.runAsync(() async {
          await tester.tap(find.text('Café medido Bolsa'));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        await variant(tester);
        await selector(tester);
        expect(find.text('Precio por 1 kg.'), findsOneWidget);
        await click(tester, 'select_variant_supplier_$supplierId');
        await tester.enterText(
          find.byKey(Key('supplier_price_$supplierId')),
          '3,25',
        );
        await click(tester, 'save_variant_suppliers_button');
        await click(tester, 'save_variant_button');
        await click(tester, 'save_article_button');
        await flush(tester);
        final saved = await tester.runAsync(
          () => h.repository.obtenerDetalle(productId),
        );
        expect(saved!.saleConfiguration, detail!.saleConfiguration);
        expect(
          saved.variantes.single.proveedores!.single.precioInformadoMenor,
          325,
        );
      } finally {
        await cleanup(tester);
      }
    },
  );
}

class _NoNetwork extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('La prueba standalone no permite HTTP/WebSocket.');
  }
}
