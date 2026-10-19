import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/articulos/variante_detalle.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_command.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_result.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_preview_form.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/inventory_article_card.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/recursos/inventory_movement_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/remaining_stock_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/widgets/remaining_stock_report_card.dart';

import '../../../support/recepcion_masiva_fixture.dart';
import '../../../support/remaining_stock_fixture.dart';

void main() {
  void stockTest(
    String name,
    AppMode mode,
    Future<void> Function(WidgetTester, RemainingStockFixture) body,
  ) {
    testWidgets('$name (${mode.name})', (tester) async {
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

  test(
    'constructores, preview y copyWith conservan la intención por defecto',
    () {
      const old = ArticuloFormVarianteResult(
        nombre: null,
        precioVenta: '1',
        costoEstandar: null,
        minimumStockAtomic: 5,
      );
      final copied = old.copyWith(codigoBarras: '0001');
      expect(copied.minimumStockAtomic, 5);
      expect(copied.minimumStock.establecer, isFalse);
      final changed = copied
          .copyWith(minimumStock: const CambioExplicito.establecer('0'))
          .copyWith(precioVenta: '2');
      expect(changed.minimumStock.valor, '0');
      final result = ArticuloFormResult(
        nombre: 'Artículo',
        variantes: [copied, changed],
        categoriaId: null,
        saleConfiguration: const UnitSaleConfiguration(),
      ).toCommand();
      expect(result.variantes.first.minimumStock.establecer, isFalse);
      expect(result.variantes.last.minimumStock.valor, '0');
    },
  );

  for (final mode in AppMode.values) {
    stockTest('A03/A18/A38 precarga, cero, vacío y varias variantes', mode, (
      tester,
      f,
    ) async {
      await _minimum(f, f.selectedId, '7');
      final before = await f.h.tracking.products.snapshot(f.productId);
      final movements = await f.h.db.select(f.h.db.inventoryMovements).get();
      await _stock(tester, f);
      expect(find.text('Existencia baja'), findsOneWidget);
      await _tap(tester, find.byKey(ValueKey(f.selectedId)));
      expect(_field(tester, 'variant_minimum_stock_field'), '7');
      expect(_minimumInput(tester).decoration!.suffixText, 'pza');
      final textField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('variant_minimum_stock_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(textField.keyboardType.decimal, isFalse);
      await _enter(tester, 'variant_minimum_stock_field', '1.5');
      expect(_field(tester, 'variant_minimum_stock_field'), '7');
      await _enter(tester, 'variant_minimum_stock_field', '-1');
      expect(_field(tester, 'variant_minimum_stock_field'), '7');
      await _enter(tester, 'variant_minimum_stock_field', '0');
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect((await _selected(f)).minimumStockAtomic, 0);
      expect(find.text('Mínimo: 0 pza'), findsOneWidget);
      expect(find.text('Existencia baja'), findsNothing);
      await _move(f, f.selectedId, -7);
      await _settle(tester);
      expect(find.text('Existencia baja'), findsOneWidget);
      await _move(f, f.selectedId, -1);
      await _settle(tester);
      expect(find.text('Existencia baja'), findsOneWidget);
      await _tap(tester, find.byKey(ValueKey(f.selectedId)));
      expect(_field(tester, 'variant_minimum_stock_field'), '0');
      await _enter(tester, 'variant_minimum_stock_field', '');
      await _tap(tester, find.byKey(const Key('save_variant_button')));
      expect((await _selected(f)).minimumStockAtomic, isNull);
      expect(find.text('Existencia baja'), findsNothing);
      for (var i = 0; i < 2; i++) {
        await _move(f, f.selectedId, 1);
        await _settle(tester);
        expect(find.text('Existencia baja'), findsNothing);
      }
      final after = await f.h.tracking.products.snapshot(f.productId);
      for (var i = 0; i < before.variantes.length; i++) {
        final expected = before.variantes[i].toJson();
        if (before.variantes[i].id == f.selectedId) {
          expected['minimum_stock_atomic'] = null;
        }
        expect(after.variantes[i].toJson(), expected);
      }
      expect(after.nombre, before.nombre);
      expect(after.saleConfiguration, before.saleConfiguration);
      expect(after.categoriaId, before.categoriaId);
      // Solo los cuatro movimientos pedidos modifican el inventario.
      expect(
        await f.h.db.select(f.h.db.inventoryMovements).get(),
        hasLength(movements.length + 4),
      );
      final updates = (await f.h.db.select(f.h.db.events).get()).where(
        (e) => e.eventType == ProductoActualizadoPayload.eventType,
      );
      expect(updates, hasLength(3)); // Configurar 7, establecer 0 y retirar.
    });

    stockTest('A02/A04/A05/A23/A40 venta, reposición y último resultado', mode, (
      tester,
      f,
    ) async {
      await _minimum(f, f.selectedId, '6');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RemainingStockReportCard(repository: f.products),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('2 variantes con seguimiento'), findsOneWidget);
      expect(find.text('Existencias bajas: 0'), findsOneWidget);
      await _tap(tester, find.text('EXISTENCIAS RESTANTES'));
      expect(find.text('Existencia baja'), findsNothing);
      await f.h.tracking.drafts.agregar(
        AgregarProductoBorradorCommand(variantId: f.selectedId),
      );
      final sale = (await f.h.db.select(f.h.db.sales).get()).single;
      await f.h.tracking.sales.confirmar(
        ConfirmarVentaCommand(
          saleId: sale.id,
          expectedDraftEventId: sale.lastEventId!,
          expectedTotalMinor: sale.totalMinor,
          paymentMethod: 'transfer',
        ),
      );
      await _settle(tester);
      expect(find.text('6 pza'), findsOneWidget);
      expect(find.text('Existencia baja'), findsOneWidget);
      expect(find.text('Existencias bajas: 1'), findsOneWidget);
      await _tap(tester, find.text('Existencias bajas'));
      expect(find.byKey(ValueKey(f.firstId)), findsNothing);
      expect(find.byKey(ValueKey(f.selectedId)), findsOneWidget);
      await _move(f, f.selectedId, -1);
      await _settle(tester);
      expect(find.text('5 pza'), findsOneWidget);
      // Reutiliza la recepción masiva real: conserva mínimo y actualiza balance.
      final rows = await DriftCatalogoEdicionMasiva(f.h.db).buscar();
      final row = rows.singleWhere((r) => r.clave.variantId == f.selectedId);
      final receipt = coordinadorRecepcion(f.h);
      final operations = await receipt.confirmar(
        batchId: 'minimum-ui-receipt',
        cambios: [cambioRecepcion(row, cantidad: 2)],
      );
      await receipt.ejecutar(operations.single);
      await _settle(tester);
      expect(
        find.text('No hay variantes con existencias bajas.'),
        findsOneWidget,
      );
      expect(find.text('Existencias bajas: 0'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Existencias bajas'),
            )
            .selected,
        isTrue,
      );
      await _tap(tester, find.text('Todas'));
      expect(find.text('7 pza'), findsOneWidget);
      expect(find.text('Mínimo: 6 pza'), findsOneWidget);
      await tester.pageBack();
      await _settle(tester);
      expect(find.text('Existencias bajas: 0'), findsOneWidget);
      await _minimum(f, f.selectedId, '7');
      await _settle(tester);
      expect(find.text('Existencias bajas: 1'), findsOneWidget);
      final events = await f.h.db.select(f.h.db.events).get();
      expect(events.where((e) => e.eventType.contains('alert')), isEmpty);
    });

    stockTest(
      'A39 cancelar mínimo y rechazar base obsoleta sin sustituirla',
      mode,
      (tester, f) async {
        await _minimum(f, f.selectedId, '5');
        await _stock(tester, f);
        final before = await fotoRecepcion(f.h.db);
        await _tap(tester, find.byKey(ValueKey(f.selectedId)));
        await _enter(tester, 'variant_minimum_stock_field', '9');
        await _tap(
          tester,
          find.byKey(const Key('close_variant_editor_button')),
        );
        expect(await fotoRecepcion(f.h.db), before);
        await _tap(tester, find.byKey(ValueKey(f.selectedId)));
        expect(_field(tester, 'variant_minimum_stock_field'), '5');
        await _enter(tester, 'variant_minimum_stock_field', '9');
        final base = (await f.h.repository.obtenerDetalle(
          f.productId,
        ))!.lastEventId!;
        await f.h.commands.asignarCodigoBarrasVariante(
          AsignarCodigoBarrasVarianteCommand(
            productId: f.productId,
            variantId: f.firstId,
            baseEventId: base,
            codigoBarras: '0999',
          ),
        );
        final changed = await fotoRecepcion(f.h.db);
        for (var attempt = 0; attempt < 2; attempt++) {
          await _tap(tester, find.byKey(const Key('save_variant_button')));
          expect(
            find.text('El artículo cambió. Vuelve a abrirlo.'),
            findsOneWidget,
          );
          expect(_field(tester, 'variant_minimum_stock_field'), '9');
          expect(await fotoRecepcion(f.h.db), changed);
        }
        expect(f.saveBases, [base, base]);
        expect((await _selected(f)).minimumStockAtomic, 5);
      },
    );

    stockTest(
      'A39 Artículos cancela el borrador y conserva la base al fallar',
      mode,
      (tester, f) async {
        await _minimum(f, f.selectedId, '5');
        await _inventory(tester, f);
        final before = await fotoRecepcion(f.h.db);
        await _tap(tester, find.byType(InventoryArticleCard));
        await _tap(tester, find.byKey(const Key('article_variant_card_1')));
        await _enter(tester, 'variant_minimum_stock_field', '9');
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        expect(find.byKey(const Key('save_article_button')), findsOneWidget);
        expect(await fotoRecepcion(f.h.db), before);
        // Reabrir el borrador conserva su intención, antes de guardar el artículo.
        await _tap(tester, find.byKey(const Key('article_variant_card_1')));
        expect(_field(tester, 'variant_minimum_stock_field'), '9');
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        await _tap(tester, find.byTooltip('Cancelar'));
        await _tap(
          tester,
          find.byKey(const Key('discard_article_changes_button')),
        );
        expect(await fotoRecepcion(f.h.db), before);
        await _tap(tester, find.byType(InventoryArticleCard));
        await _tap(tester, find.byKey(const Key('article_variant_card_1')));
        expect(_field(tester, 'variant_minimum_stock_field'), '5');
        await _enter(tester, 'variant_minimum_stock_field', '9');
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        final base = (await f.h.repository.obtenerDetalle(
          f.productId,
        ))!.lastEventId!;
        await f.h.commands.asignarCodigoBarrasVariante(
          AsignarCodigoBarrasVarianteCommand(
            productId: f.productId,
            variantId: f.firstId,
            baseEventId: base,
            codigoBarras: '0888',
          ),
        );
        final changed = await fotoRecepcion(f.h.db);
        for (var attempt = 0; attempt < 2; attempt++) {
          await _tap(tester, find.byKey(const Key('save_article_button')));
          expect(
            find.text('El artículo cambió. Vuelve a abrirlo.'),
            findsOneWidget,
          );
          expect(await fotoRecepcion(f.h.db), changed);
        }
        expect(f.saveBases, [base, base]);
        expect((await _selected(f)).minimumStockAtomic, 5);
      },
    );

    stockTest(
      'A25 mínimo dormido se conserva y se recupera desde Artículos',
      mode,
      (tester, f) async {
        await _minimum(f, f.selectedId, '7');
        await _stock(tester, f);
        await _tap(tester, find.byKey(ValueKey(f.selectedId)));
        await _enter(tester, 'variant_minimum_stock_field', '1');
        await _tap(
          tester,
          find.byKey(const Key('variant_inventory_tracking_switch')),
        );
        expect(
          find.byKey(const Key('variant_minimum_stock_field')),
          findsNothing,
        );
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        var selected = await _selected(f);
        expect(selected.minimumStockAtomic, 7);
        expect(selected.inventoryItemId, isNull);
        expect(find.byKey(ValueKey(f.selectedId)), findsNothing);
        await _inventory(tester, f);
        await _tap(tester, find.byType(InventoryArticleCard));
        await _tap(tester, find.byKey(const Key('article_variant_card_1')));
        await _tap(
          tester,
          find.byKey(const Key('variant_inventory_tracking_switch')),
        );
        expect(_field(tester, 'variant_minimum_stock_field'), '7');
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        await _tap(tester, find.byKey(const Key('save_article_button')));
        selected = await _selected(f);
        expect(selected.minimumStockAtomic, 7);
        expect(selected.inventoryItemId, isNotNull);
        await _stock(tester, f);
        expect(find.text('Existencia baja'), findsOneWidget);
      },
    );

    stockTest(
      'A06/A38 kg de inventario con venta en gramos en ambos accesos',
      mode,
      (tester, f) async {
        final created = await f.h.tracking.create(
          name: 'A granel',
          initial: '1.501',
          unit: InventoryUnitIds.kilogram,
          sale: MeasuredSaleConfiguration(
            saleUnitId: InventoryUnitIds.gram,
            priceReferenceQuantityAtomic: 1,
          ),
        );
        await _minimum(
          f,
          created.variantId,
          '1.5',
          productId: created.productId,
        );
        await _stock(tester, f);
        expect(find.text('Mínimo: 1.5 kg'), findsOneWidget);
        expect(find.text('Existencia baja'), findsNothing);
        await _move(f, created.variantId, -1, productId: created.productId);
        await _settle(tester);
        expect(find.text('Existencia baja'), findsOneWidget);
        await _tap(tester, find.byKey(ValueKey(created.variantId)));
        expect(_field(tester, 'variant_minimum_stock_field'), '1.5');
        expect(_minimumInput(tester).decoration!.suffixText, 'kg');
        expect(_minimumInput(tester).keyboardType.decimal, isTrue);
        await _enter(tester, 'variant_minimum_stock_field', '1,501');
        await _enter(tester, 'variant_minimum_stock_field', '1,5011');
        expect(_field(tester, 'variant_minimum_stock_field'), '1,501');
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        expect(
          (await f.h.repository.obtenerDetalle(
            created.productId,
          ))!.variantes.single.minimumStockAtomic,
          1501,
        );
        await _inventory(tester, f);
        await _tap(
          tester,
          find.widgetWithText(InventoryArticleCard, 'A granel'),
        );
        await _tap(tester, find.byKey(const Key('article_variant_card_0')));
        expect(
          tester
              .widget<VariantEditorScreen>(find.byType(VariantEditorScreen))
              .inventoryUnit
              .id,
          InventoryUnitIds.kilogram,
        );
        expect(_field(tester, 'variant_minimum_stock_field'), '1.501');
        await _enter(tester, 'variant_minimum_stock_field', '1,5');
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        await _tap(tester, find.byKey(const Key('save_article_button')));
        final detail = (await f.h.repository.obtenerDetalle(
          created.productId,
        ))!;
        expect(detail.variantes.single.minimumStockAtomic, 1500);
        expect(detail.variantes.single.inventoryItemId, created.resourceId);
        expect(detail.saleConfiguration.saleUnitId, InventoryUnitIds.gram);
      },
    );

    stockTest('A19 alta sencilla sin mínimo y avanzada con dos mínimos', mode, (
      tester,
      f,
    ) async {
      await _newArticle(tester, f);
      await _enter(tester, 'article_name_field', 'Sencillo');
      await _enter(tester, 'article_price_field', '10');
      await _tap(tester, find.byKey(const Key('save_article_button')));
      final simple = (await f.h.db.select(f.h.db.products).get()).singleWhere(
        (p) => p.name == 'Sencillo',
      );
      expect(
        (await f.h.repository.obtenerDetalle(
          simple.id,
        ))!.variantes.single.minimumStockAtomic,
        isNull,
      );
      await _newArticle(tester, f);
      await _enter(tester, 'article_name_field', 'Nuevo con mínimos');
      await _tap(tester, find.text('Avanzado'));
      for (var index = 0; index < 2; index++) {
        await _tap(
          tester,
          index == 0
              ? find.byKey(const Key('article_variant_card_0'))
              : find.byKey(const Key('add_article_variant_button')),
        );
        await _enter(tester, 'variant_name_field', 'Variante $index');
        await _enter(tester, 'variant_sale_price_field', '10');
        await _tap(
          tester,
          find.byKey(const Key('variant_inventory_tracking_switch')),
        );
        await _enter(
          tester,
          'variant_minimum_stock_field',
          index == 0 ? '0' : '5',
        );
        await _tap(tester, find.byKey(const Key('save_variant_button')));
      }
      await _tap(tester, find.byKey(const Key('save_article_button')));
      final product = (await f.h.db.select(f.h.db.products).get()).singleWhere(
        (p) => p.name == 'Nuevo con mínimos',
      );
      final detail = (await f.h.repository.obtenerDetalle(product.id))!;
      expect(detail.variantes.map((v) => v.minimumStockAtomic), [0, 5]);
      expect(detail.variantes.map((v) => v.id).toSet(), hasLength(2));
      expect(detail.variantes.every((v) => v.inventoryItemId != null), isTrue);
      await _stock(tester, f);
      expect(find.text('Existencias bajas: 2'), findsOneWidget);
    });

    stockTest('A39 movimiento guardado sobrevive a cancelar el mínimo', mode, (
      tester,
      f,
    ) async {
      await _minimum(f, f.selectedId, '7');
      await _stock(tester, f);
      await _tap(tester, find.byKey(ValueKey(f.selectedId)));
      await _enter(tester, 'variant_minimum_stock_field', '100');
      await _tap(
        tester,
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(find.byType(InventoryMovementScreen), findsOneWidget);
      await _enter(tester, 'inventory_initial_quantity_field', '1');
      await _tap(
        tester,
        find.byKey(const Key('register_inventory_movement_button')),
      );
      expect(find.text('8 pza'), findsOneWidget);
      await _tap(tester, find.byKey(const Key('close_variant_editor_button')));
      expect((await _selected(f)).minimumStockAtomic, 7);
      expect(find.text('8 pza'), findsOneWidget);
      expect(find.text('Existencia baja'), findsNothing);
    });

    stockTest(
      'A14/A20/A41 lectura repetida y barcode no promueven base legada',
      mode,
      (tester, f) async {
        // Reproduce una creación histórica tipada con su propio recurso.
        await f.h.tracking.inventoryCommands.crearRecurso(
          const CrearRecursoInventarioCommand(
            nombre: 'Recurso legado UI',
            defaultUnitId: InventoryUnitIds.piece,
            quantityDeltaAtomic: 3,
          ),
        );
        final resource = (await f.resources.watchRecursos().first).singleWhere(
          (r) => r.nombre == 'Recurso legado UI',
        );
        const productId = 'legacy-ui-product';
        const variantId = 'aaaaaaaa-0000-4000-8000-000000000001';
        final payload = ProductoCreadoPayload.create(
          nombre: 'Legado UI',
          categoriaId: null,
          saleConfiguration: const UnitSaleConfiguration(),
          dependenciasInventario: [
            ProductoCreadoInventarioDependencia(refId: resource.id),
          ],
          variantes: [
            ProductoCreadoVariante.create(
              id: variantId,
              nombre: null,
              precioVentaMenor: 100,
              costoEstandarMenor: null,
              orden: 0,
              inventoryItemId: resource.id,
            ),
          ],
        );
        await f.h.events.appendAndApply(
          SyncEvent(
            eventId: 'legacy-ui-create',
            aggregateType: 'product',
            aggregateId: productId,
            eventType: ProductoCreadoPayload.eventType,
            deviceId: 'old',
            userId: 'user',
            createdAtLocal: DateTime(2026),
            baseVersion: 1,
            payload: payload.toJson(),
          ),
          refs: [
            const LocalEventRef.affects(refType: 'product', refId: productId),
          ],
        );
        final before = await fotoRecepcion(f.h.db);
        await _stock(tester, f);
        await _tap(tester, find.text('Existencias bajas'));
        expect(
          find.text('No hay variantes con existencias bajas.'),
          findsOneWidget,
        );
        await _tap(tester, find.text('Todas'));
        await _tap(tester, find.byKey(const ValueKey(variantId)));
        expect(_field(tester, 'variant_minimum_stock_field'), '');
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        expect(await fotoRecepcion(f.h.db), before);
        await _tap(tester, find.byKey(const ValueKey(variantId)));
        await _enter(tester, 'variant_barcode_field', '00999');
        await _tap(tester, find.byKey(const Key('save_variant_button')));
        final state = await f.h.tracking.products.snapshot(productId);
        expect(state.knowsMinimumStock, isFalse);
        expect(state.variantes.single.minimumStockAtomic, isNull);
        final event = (await f.h.db.select(f.h.db.events).get()).last;
        final updated = ProductoActualizadoPayload.fromJson(
          Map<String, Object?>.from(jsonDecode(event.payload) as Map),
        );
        expect(updated.before.knowsMinimumStock, isFalse);
        expect(updated.after.knowsMinimumStock, isFalse);
        expect(updated.after.variantes.single.codigoBarras, '00999');
      },
    );

    for (final size in [const Size(320, 740), const Size(1024, 768)]) {
      stockTest('A38/A40 mínimo y distintivo con texto grande en $size', mode, (
        tester,
        f,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await _minimum(f, f.firstId, '3');
        await _minimum(f, f.selectedId, '7');
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: RemainingStockScreen(
              repository: f.products,
              variantEditor: f.editor,
            ),
          ),
        );
        await _settle(tester);
        await _tap(tester, find.text('Existencias bajas'));
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(f.selectedId)),
          200,
        );
        await _settle(tester);
        expect(find.text('Mínimo: 7 pza'), findsOneWidget);
        await _tap(tester, find.byKey(ValueKey(f.selectedId)));
        await tester.ensureVisible(
          find.byKey(const Key('variant_minimum_stock_field')),
        );
        await _settle(tester);
        expect(_field(tester, 'variant_minimum_stock_field'), '7');
        expect(tester.takeException(), isNull);
      });
    }

    stockTest(
      'A26 contador excluye recurso inactivo, variante retirada y producto',
      mode,
      (tester, f) async {
        await _minimum(f, f.firstId, '3');
        await _minimum(f, f.selectedId, '7');
        await _stock(tester, f);
        expect(find.text('Existencias bajas: 2'), findsOneWidget);
        final selected = await _selected(f);
        await (f.h.db.update(f.h.db.inventoryItems)
              ..where((i) => i.id.equals(selected.inventoryItemId!)))
            .write(const InventoryItemsCompanion(active: Value(false)));
        await _settle(tester);
        expect(find.text('Existencias bajas: 1'), findsOneWidget);
        await (f.h.db.update(f.h.db.productVariants)
              ..where((v) => v.id.equals(f.firstId)))
            .write(const ProductVariantsCompanion(active: Value(false)));
        await _settle(tester);
        expect(find.text('Existencias bajas: 0'), findsOneWidget);
        await (f.h.db.update(f.h.db.products)
              ..where((p) => p.id.equals(f.productId)))
            .write(const ProductsCompanion(active: Value(false)));
        await _settle(tester);
        await _tap(tester, find.text('Existencias bajas'));
        expect(
          find.text('No hay variantes con existencias bajas.'),
          findsOneWidget,
        );
        final rows = await f.h.db.select(f.h.db.productVariants).get();
        expect(
          rows.singleWhere((v) => v.id == f.firstId).minimumStockAtomic,
          3,
        );
        expect(
          rows.singleWhere((v) => v.id == f.selectedId).minimumStockAtomic,
          7,
        );
      },
    );
  }
}

Future<ArticuloFormResult> _preview(
  RemainingStockFixture f,
  String productId,
) async => ArticuloPreviewForm.fromDetalle(
  (await f.h.repository.obtenerDetalle(productId))!,
  await f.resources.watchRecursos().first,
);

Future<void> _minimum(
  RemainingStockFixture f,
  String variantId,
  String? value, {
  String? productId,
}) async {
  final id = productId ?? f.productId;
  final detail = (await f.h.repository.obtenerDetalle(id))!;
  final initial = await _preview(f, id);
  final result = ArticuloFormResult(
    nombre: initial.nombre,
    categoriaId: initial.categoriaId,
    saleConfiguration: initial.saleConfiguration,
    variantes: [
      for (final v in initial.variantes)
        v.id == variantId
            ? v.copyWith(minimumStock: CambioExplicito.establecer(value))
            : v,
    ],
  );
  await f.h.commands.actualizarArticulo(
    productId: id,
    baseEventId: detail.lastEventId!,
    variantIds: result.variantes.map((v) => v.id).toList(),
    command: result.toCommand(),
  );
}

Future<VarianteDetalle> _selected(RemainingStockFixture f) async =>
    (await f.h.repository.obtenerDetalle(
      f.productId,
    ))!.variantes.singleWhere((v) => v.id == f.selectedId);

Future<void> _move(
  RemainingStockFixture f,
  String variantId,
  int delta, {
  String? productId,
}) async {
  final detail = (await f.h.repository.obtenerDetalle(
    productId ?? f.productId,
  ))!;
  await f.h.tracking.inventoryCommands.registrarMovimiento(
    RegistrarMovimientoInventarioCommand(
      inventoryItemId: detail.variantes
          .singleWhere((v) => v.id == variantId)
          .inventoryItemId!,
      movementType: delta > 0
          ? TipoMovimientoInventario.stockReceipt
          : TipoMovimientoInventario.manualAdjustment,
      quantityDeltaAtomic: delta,
      movementReason: 'Prueba mínimo',
    ),
  );
}

Future<void> _stock(WidgetTester tester, RemainingStockFixture f) async {
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

Future<void> _inventory(WidgetTester tester, RemainingStockFixture f) async {
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
}

Future<void> _newArticle(WidgetTester tester, RemainingStockFixture f) async {
  final units = await f.units.obtenerUnidadesActivas();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ArticleFormScreen(
                  categorias: const [],
                  unidadesVenta: units,
                  onSave: (result) =>
                      f.h.commands.crearArticulo(result.toCommand()),
                ),
              ),
            ),
            child: const Text('Crear'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Crear'));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pump();
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

TextField _minimumInput(WidgetTester tester) => tester.widget<TextField>(
  find.descendant(
    of: find.byKey(const Key('variant_minimum_stock_field')),
    matching: find.byType(TextField),
  ),
);
