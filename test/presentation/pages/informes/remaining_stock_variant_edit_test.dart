import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/inventario/inventory_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/repositories/proveedor_repository.dart';
import 'package:pos_flutter/domain/repositories/recurso_inventario_repository.dart';
import 'package:pos_flutter/domain/repositories/unidad_inventario_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/inventory_article_card.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/recursos/inventory_movement_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/remaining_stock_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/reports_screen.dart';

import '../../../support/remaining_stock_fixture.dart';

void main() {
  void stockTest(
    String name,
    Future<void> Function(WidgetTester, RemainingStockFixture) body, {
    AppMode mode = AppMode.standalone,
  }) {
    testWidgets(name, (tester) async {
      final f = RemainingStockFixture(mode: mode);
      try {
        await tester.runAsync(() async {
          await f.seed();
          await body(tester, f);
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(f.h.dispose);
      }
    });
  }

  for (final mode in AppMode.values) {
    stockTest(
      'Informes → variante correcta → guardado definitivo en ${mode.name}',
      mode: mode,
      (tester, f) async {
        getIt.pushNewScope();
        try {
          getIt.registerSingleton<ProductoCommandService>(f.commands);
          getIt.registerSingleton<RecursoInventarioRepository>(f.resources);
          getIt.registerSingleton<UnidadInventarioRepository>(f.units);
          getIt.registerSingleton<InventoryCommandService>(
            f.h.tracking.inventoryCommands,
          );
          getIt.registerSingleton<ProveedorRepository>(f.suppliers);
          getIt.registerSingleton<AppConfigController>(f.h.tracking.config);
          await _pumpReports(tester, f);
          expect(find.text('2 variantes con seguimiento'), findsOneWidget);
          await _tap(tester, find.text('EXISTENCIAS RESTANTES'));
          final before = await f.h.tracking.products.snapshot(f.productId);
          final movements = await f.h.db
              .select(f.h.db.inventoryMovements)
              .get();
          await _tap(tester, find.byKey(ValueKey(f.selectedId)));
          expect(find.byType(ArticleFormScreen), findsNothing);
          expect(_field(tester, 'variant_name_field'), 'Grande');
          expect(_field(tester, 'variant_sale_price_field'), '25.50');
          expect(_field(tester, 'variant_standard_cost_field'), '11.22');
          expect(_field(tester, 'variant_barcode_field'), '0002');
          expect(find.text('7 pza'), findsOneWidget);
          expect(
            find.byKey(const Key('variant_initial_stock_field')),
            findsNothing,
          );
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('delete_variant_button')),
                )
                .onPressed,
            isNull,
          );
          final editor = tester.widget<VariantEditorScreen>(
            find.byType(VariantEditorScreen),
          );
          expect(editor.onCreateInventoryResource, isNotNull);
          expect(editor.proveedorRepository, same(f.suppliers));
          expect(editor.initialValue!.proveedores, isNotEmpty);
          await _enter(tester, 'variant_name_field', 'Grande nueva');
          await _enter(tester, 'variant_sale_price_field', '27.34');
          await _enter(tester, 'variant_standard_cost_field', '12.31');
          await _enter(tester, 'variant_barcode_field', '00022');
          await _tap(tester, find.byKey(const Key('save_variant_button')));
          expect(find.byType(VariantEditorScreen), findsNothing);
          expect(find.text('Grande nueva'), findsOneWidget);
          expect(find.text('7 pza'), findsOneWidget);
          expect(f.detailReads, [f.productId]);
          expect(f.saveBases, [f.initialBase]);
          final after = await f.h.tracking.products.snapshot(f.productId);
          expect(after.nombre, before.nombre);
          expect(after.categoriaId, before.categoriaId);
          expect(after.saleConfiguration, before.saleConfiguration);
          expect(
            after.variantes.map((v) => v.id),
            before.variantes.map((v) => v.id),
          );
          expect(
            after.variantes.map((v) => v.orden),
            before.variantes.map((v) => v.orden),
          );
          for (final variant in before.variantes.where(
            (v) => v.id != f.selectedId,
          )) {
            expect(
              after.variantes.singleWhere((v) => v.id == variant.id).toJson(),
              variant.toJson(),
            );
          }
          final edited = after.variantes.singleWhere(
            (v) => v.id == f.selectedId,
          );
          final original = before.variantes.singleWhere(
            (v) => v.id == f.selectedId,
          );
          expect(edited.nombre, 'Grande nueva');
          expect(edited.precioVentaMenor, 2734);
          expect(edited.costoEstandarMenor, 1231);
          expect(edited.codigoBarras, '00022');
          expect(edited.inventoryItemId, original.inventoryItemId);
          expect(edited.toJson()['suppliers'], original.toJson()['suppliers']);
          expect(
            await f.h.db.select(f.h.db.inventoryMovements).get(),
            movements,
          );
          final events = await f.h.db.select(f.h.db.events).get();
          expect(events, hasLength(f.initialEvents + 1));
          final event = events.singleWhere(
            (e) => e.eventType == ProductoActualizadoPayload.eventType,
          );
          expect(
            event.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          final payload = ProductoActualizadoPayload.fromJson(
            (jsonDecode(event.payload) as Map).cast<String, Object?>(),
          );
          expect(payload.baseEventId, f.initialBase);
          final refs = await f.h.db.select(f.h.db.eventRefs).get();
          if (mode == AppMode.standalone) {
            expect(refs, isEmpty);
          } else {
            expect(
              refs.where((ref) => ref.eventId == event.eventId),
              isNotEmpty,
            );
          }
        } finally {
          await getIt.popScope();
        }
      },
    );
  }

  stockTest('cancelar conserva el artículo y no emite actualización', (
    tester,
    f,
  ) async {
    await _pumpStock(tester, f);
    await _openSelected(tester, f);
    await _enter(tester, 'variant_name_field', 'Sin guardar');
    await _tap(tester, find.byKey(const Key('close_variant_editor_button')));
    expect(find.text('Grande'), findsOneWidget);
    expect(f.saveBases, isEmpty);
    expect(
      await f.h.db.select(f.h.db.events).get(),
      hasLength(f.initialEvents),
    );
  });

  stockTest('error de carga conserva el listado y permite volver a abrir', (
    tester,
    f,
  ) async {
    f.beforeDetail = () async => throw StateError('Lectura fallida');
    await _pumpStock(tester, f);
    await _openSelected(tester, f);
    expect(
      find.textContaining('No se pudo cargar la variante.'),
      findsOneWidget,
    );
    expect(find.byType(VariantEditorScreen), findsNothing);
    expect(find.text('Grande'), findsOneWidget);
    expect(find.text('7 pza'), findsOneWidget);
    f.beforeDetail = null;
    await _openSelected(tester, f);
    expect(_field(tester, 'variant_name_field'), 'Grande');
    expect(f.detailReads, [f.productId, f.productId]);
    expect(
      await f.h.db.select(f.h.db.events).get(),
      hasLength(f.initialEvents),
    );
  });

  for (final unavailable in [
    'artículo',
    'variante',
    'seguimiento',
    'recurso',
  ]) {
    stockTest('rechaza selección obsoleta por $unavailable no disponible', (
      tester,
      f,
    ) async {
      final stale = await f.h.repository.watchArticulos().first;
      f.catalog = () => Stream.value(stale);
      await _pumpStock(tester, f);
      switch (unavailable) {
        case 'artículo':
          await (f.h.db.update(f.h.db.products)
                ..where((p) => p.id.equals(f.productId)))
              .write(const ProductsCompanion(active: Value(false)));
        case 'variante':
          await (f.h.db.update(f.h.db.productVariants)
                ..where((v) => v.id.equals(f.selectedId)))
              .write(const ProductVariantsCompanion(active: Value(false)));
        case 'seguimiento':
          await (f.h.db.update(
            f.h.db.productVariants,
          )..where((v) => v.id.equals(f.selectedId))).write(
            const ProductVariantsCompanion(inventoryItemId: Value(null)),
          );
        case 'recurso':
          final detail = (await f.h.repository.obtenerDetalle(f.productId))!;
          final resourceId = detail.variantes
              .singleWhere((v) => v.id == f.selectedId)
              .inventoryItemId!;
          await (f.h.db.update(f.h.db.inventoryItems)
                ..where((r) => r.id.equals(resourceId)))
              .write(const InventoryItemsCompanion(active: Value(false)));
      }
      await _openSelected(tester, f);
      expect(find.byType(VariantEditorScreen), findsNothing);
      expect(
        find.textContaining('No se pudo cargar la variante.'),
        findsOneWidget,
      );
      expect(f.saveBases, isEmpty);
      expect(
        await f.h.db.select(f.h.db.events).get(),
        hasLength(f.initialEvents),
      );
    });
  }

  stockTest('varios toques durante la carga abren un solo editor', (
    tester,
    f,
  ) async {
    final gate = Completer<void>();
    f.beforeDetail = () => gate.future;
    await _pumpStock(tester, f);
    await tester.tap(find.byKey(ValueKey(f.selectedId)));
    await tester.tap(find.byKey(ValueKey(f.firstId)));
    await tester.tap(find.byKey(ValueKey(f.selectedId)));
    await tester.pump();
    expect(f.detailReads, [f.productId]);
    gate.complete();
    await _settle(tester);
    expect(find.byType(VariantEditorScreen), findsOneWidget);
    expect(_field(tester, 'variant_name_field'), 'Grande');
    await _tap(tester, find.byKey(const Key('close_variant_editor_button')));
    await _tap(tester, find.byKey(ValueKey(f.firstId)));
    expect(_field(tester, 'variant_name_field'), 'Chico');
    expect(f.detailReads, hasLength(2));
  });

  stockTest('salir del listado descarta una carga tardía', (tester, f) async {
    // El coordinador se inyecta al abrir la ruta para controlar su lectura.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RemainingStockScreen(
                    repository: f.products,
                    variantEditor: f.editor,
                  ),
                ),
              ),
              child: const Text('Abrir existencias'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Abrir existencias'));
    final gate = Completer<void>();
    f.beforeDetail = () => gate.future;
    await tester.tap(find.byKey(ValueKey(f.selectedId)));
    await tester.pump();
    await tester.pageBack();
    await _settle(tester);
    gate.complete();
    await _settle(tester);
    expect(find.byType(VariantEditorScreen), findsNothing);
    expect(find.text('Abrir existencias'), findsOneWidget);
    expect(f.saveBases, isEmpty);
  });

  stockTest(
    'fallo transaccional conserva captura y permite reintentar con la misma base',
    (tester, f) async {
      await _pumpStock(tester, f);
      await _openSelected(tester, f);
      await _enter(tester, 'variant_name_field', 'Captura conservada');
      f.h.failAfterProductApply = true;
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect(find.byType(VariantEditorScreen), findsOneWidget);
      expect(_field(tester, 'variant_name_field'), 'Captura conservada');
      expect(find.textContaining('fallo inyectado'), findsOneWidget);
      expect(
        await f.h.db.select(f.h.db.events).get(),
        hasLength(f.initialEvents),
      );
      expect(
        (await f.h.repository.obtenerDetalle(f.productId))!.lastEventId,
        f.initialBase,
      );
      f.h.failAfterProductApply = false;
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect(find.text('Captura conservada'), findsOneWidget);
      expect(find.byType(VariantEditorScreen), findsNothing);
      expect(f.saveBases, [f.initialBase, f.initialBase]);
    },
  );

  stockTest(
    'guardado pendiente bloquea doble envío, cerrar y regreso del sistema',
    (tester, f) async {
      final gate = Completer<void>();
      f.beforeSave = () => gate.future;
      await _pumpStock(tester, f);
      await _openSelected(tester, f);
      await _enter(tester, 'variant_name_field', 'Una vez');
      await tester.tap(find.byKey(const Key('save_variant_button')));
      await tester.tap(find.byKey(const Key('save_variant_button')));
      await tester.pump();
      expect(f.saveBases, [f.initialBase]);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('close_variant_editor_button')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save_variant_button')))
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(VariantEditorScreen), findsOneWidget);
      expect(
        await f.h.db.select(f.h.db.events).get(),
        hasLength(f.initialEvents),
      );
      gate.complete();
      await _settle(tester);
      expect(find.byType(VariantEditorScreen), findsNothing);
      expect(find.text('Una vez'), findsOneWidget);
      expect(
        await f.h.db.select(f.h.db.events).get(),
        hasLength(f.initialEvents + 1),
      );
    },
  );

  stockTest(
    'base obsoleta exige reabrir y nunca sobrescribe ni cambia la base',
    (tester, f) async {
      await _pumpStock(tester, f);
      await _openSelected(tester, f);
      await _enter(tester, 'variant_name_field', 'Edición pendiente');
      await f.h.commands.asignarCodigoBarrasVariante(
        AsignarCodigoBarrasVarianteCommand(
          productId: f.productId,
          variantId: f.firstId,
          baseEventId: f.initialBase,
          codigoBarras: '0999',
        ),
      );
      final changedBase = (await f.h.repository.obtenerDetalle(
        f.productId,
      ))!.lastEventId!;
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect(
        find.text('El artículo cambió. Vuelve a abrirlo.'),
        findsOneWidget,
      );
      expect(_field(tester, 'variant_name_field'), 'Edición pendiente');
      expect(f.saveBases, [f.initialBase]);
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect(f.saveBases, [f.initialBase, f.initialBase]);
      expect(f.detailReads, [f.productId]);
      expect(
        await f.h.db.select(f.h.db.events).get(),
        hasLength(f.initialEvents + 1),
      );
      final unchanged = (await f.h.repository.obtenerDetalle(f.productId))!;
      expect(
        unchanged.variantes.singleWhere((v) => v.id == f.selectedId).nombre,
        'Grande',
      );
      expect(
        unchanged.variantes.singleWhere((v) => v.id == f.firstId).codigoBarras,
        '0999',
      );
      await _tap(tester, find.byKey(const Key('close_variant_editor_button')));
      await _openSelected(tester, f);
      await _enter(tester, 'variant_name_field', 'Reabierta');
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect(f.saveBases.last, changedBase);
      expect(find.text('Reabierta'), findsOneWidget);
    },
  );

  stockTest('conserva validación de nombres duplicados y precio obligatorio', (
    tester,
    f,
  ) async {
    await _pumpStock(tester, f);
    await _openSelected(tester, f);
    await _enter(tester, 'variant_name_field', ' CHICO ');
    await _tap(tester, find.byKey(const Key('save_variant_button')));
    expect(
      find.text('Ya existe una variante con este nombre.'),
      findsOneWidget,
    );
    expect(f.saveBases, isEmpty);
    await _enter(tester, 'variant_name_field', 'Grande');
    await _enter(tester, 'variant_sale_price_field', '');
    await _tap(tester, find.byKey(const Key('save_variant_button')));
    expect(find.byType(VariantEditorScreen), findsOneWidget);
    expect(f.saveBases, isEmpty);
  });

  stockTest(
    'guardar sin seguimiento retira solo la variante del listado reactivo',
    (tester, f) async {
      await _pumpStock(tester, f);
      await _openSelected(tester, f);
      await _tap(
        tester,
        find.byKey(const Key('variant_inventory_tracking_switch')),
      );
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect(find.byType(VariantEditorScreen), findsNothing);
      expect(find.text('Grande'), findsNothing);
      expect(find.text('Chico'), findsOneWidget);
      final detail = (await f.h.repository.obtenerDetalle(f.productId))!;
      expect(detail.variantes, hasLength(4));
      expect(
        detail.variantes
            .singleWhere((v) => v.id == f.selectedId)
            .inventoryItemId,
        isNull,
      );
      expect(
        await f.h.db.select(f.h.db.inventoryMovements).get(),
        hasLength(2),
      );
    },
  );

  for (final saveArticle in [false, true]) {
    stockTest(
      'movimiento independiente se conserva al ${saveArticle ? 'guardar' : 'cancelar'} la variante',
      (tester, f) async {
        await _pumpStock(tester, f);
        await _openSelected(tester, f);
        await _enter(tester, 'variant_name_field', 'Con movimiento');
        expect(
          find.byKey(const Key('variant_initial_stock_field')),
          findsNothing,
        );
        await _tap(
          tester,
          find.byKey(const Key('register_inventory_movement_button')),
        );
        expect(find.byType(InventoryMovementScreen), findsOneWidget);
        expect(
          find.byKey(const Key('inventory_movement_independent_note')),
          findsOneWidget,
        );
        await _enter(tester, 'inventory_initial_quantity_field', '4');
        await _tap(
          tester,
          find.byKey(const Key('register_inventory_movement_button')),
        );
        expect(find.byType(VariantEditorScreen), findsOneWidget);
        expect(find.text('11 pza'), findsOneWidget);
        await _tap(
          tester,
          find.byKey(
            Key(
              saveArticle
                  ? 'save_variant_button'
                  : 'close_variant_editor_button',
            ),
          ),
        );
        expect(find.text('11 pza'), findsOneWidget);
        expect(
          find.text(saveArticle ? 'Con movimiento' : 'Grande'),
          findsOneWidget,
        );
        final events = await f.h.db.select(f.h.db.events).get();
        expect(
          events.where(
            (e) => e.eventType == ProductoActualizadoPayload.eventType,
          ),
          hasLength(saveArticle ? 1 : 0),
        );
        expect(
          await f.h.db.select(f.h.db.inventoryMovements).get(),
          hasLength(3),
        );
        expect(f.saveBases, saveArticle ? [f.initialBase] : isEmpty);
      },
    );
  }

  stockTest('usa kg del recurso aunque la venta medida esté en gramos', (
    tester,
    f,
  ) async {
    final sale = MeasuredSaleConfiguration(
      saleUnitId: InventoryUnitIds.gram,
      priceReferenceQuantityAtomic: 1,
    );
    final created = await f.h.tracking.create(
      name: 'A granel',
      initial: '2.5',
      unit: InventoryUnitIds.kilogram,
      sale: sale,
    );
    await _pumpStock(tester, f);
    await _tap(tester, find.byKey(ValueKey(created.variantId)));
    final editor = tester.widget<VariantEditorScreen>(
      find.byType(VariantEditorScreen),
    );
    expect(editor.inventoryUnit.id, InventoryUnitIds.kilogram);
    expect(editor.saleConfiguration, sale);
    expect(find.text('2.5 kg'), findsOneWidget);
    await _enter(tester, 'variant_barcode_field', '000123');
    await _tap(tester, find.byKey(const Key('save_variant_button')));
    expect(find.text('2.5 kg'), findsOneWidget);
    final detail = (await f.h.repository.obtenerDetalle(created.productId))!;
    expect(detail.saleConfiguration, sale);
    expect(detail.variantes.single.inventoryItemId, created.resourceId);
    expect(detail.variantes.single.codigoBarras, '000123');
  });

  stockTest('guardar conserva el desplazamiento del listado', (
    tester,
    f,
  ) async {
    await f.h.commands.crearArticulo(
      CrearArticuloCommand.conVariantes(
        nombre: 'Filas',
        saleConfiguration: const UnitSaleConfiguration(),
        variantes: List.generate(
          25,
          (i) => CrearArticuloVarianteCommand(
            nombre: 'Fila ${i.toString().padLeft(2, '0')}',
            precioVenta: '1',
            costoEstandar: null,
            inventoryUnitId: InventoryUnitIds.piece,
          ),
        ),
      ),
    );
    await _pumpStock(tester, f);
    await tester.scrollUntilVisible(find.text('Fila 20'), 300);
    await _settle(tester);
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    final offset = controller.offset;
    expect(offset, greaterThan(0));
    await _tap(tester, find.text('Fila 20'));
    await _enter(tester, 'variant_name_field', 'Fila editada');
    await _tap(tester, find.byKey(const Key('save_variant_button')));
    expect(controller.offset, closeTo(offset, 0.1));
    expect(find.text('Fila editada'), findsOneWidget);
  });

  stockTest(
    'Inventario guarda primero el borrador y persiste solo al guardar el artículo',
    (tester, f) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InventoryManagementScreen(
            categoriaRepository: CategoriaRepositoryImpl(
              categoriaDao: f.h.db.categoriaDao,
            ),
            productoRepository: f.products,
            productoCommandService: f.commands,
            recursoInventarioRepository: f.resources,
            unidadInventarioRepository: f.units,
            inventoryCommandService: f.h.tracking.inventoryCommands,
            proveedorRepository: f.suppliers,
            appConfigController: f.h.tracking.config,
          ),
        ),
      );
      await _settle(tester);
      await _tap(tester, find.byType(InventoryArticleCard));
      expect(find.byType(ArticleFormScreen), findsOneWidget);
      await _tap(tester, find.byKey(const Key('article_variant_card_1')));
      expect(
        tester
            .widget<VariantEditorScreen>(find.byType(VariantEditorScreen))
            .onSave,
        isNull,
      );
      await _enter(tester, 'variant_name_field', 'Desde Inventario');
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect(find.byType(ArticleFormScreen), findsOneWidget);
      expect(find.byType(VariantEditorScreen), findsNothing);
      expect(f.saveBases, isEmpty);
      expect(
        await f.h.db.select(f.h.db.events).get(),
        hasLength(f.initialEvents),
      );
      expect(
        (await f.h.repository.obtenerDetalle(f.productId))!.variantes[1].nombre,
        'Grande',
      );
      await _tap(tester, find.byKey(const Key('save_article_button')));
      expect(f.saveBases, [f.initialBase]);
      expect(
        (await f.h.repository.obtenerDetalle(f.productId))!.variantes[1].nombre,
        'Desde Inventario',
      );
      expect(
        await f.h.db.select(f.h.db.events).get(),
        hasLength(f.initialEvents + 1),
      );
    },
  );
}

Future<void> _pumpStock(WidgetTester tester, RemainingStockFixture f) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RemainingStockScreen(
        repository: f.products,
        variantEditor: f.editor,
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _pumpReports(WidgetTester tester, RemainingStockFixture f) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReportsScreen(
          repository: _SalesRepository(),
          productoRepository: f.products,
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _openSelected(WidgetTester tester, RemainingStockFixture f) =>
    _tap(tester, find.byKey(ValueKey(f.selectedId)));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

class _SalesRepository implements ConfirmedSaleRepository {
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value([]);
}

// Las consultas de Drift usan tareas reales, además de los frames de Flutter.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}
