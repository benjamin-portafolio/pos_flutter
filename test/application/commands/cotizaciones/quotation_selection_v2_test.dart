import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/cotizaciones/guardar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_guardada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/cotizacion_recuperada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/sale_item_snapshot.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/models/quotation_display.dart';
import '../../../support/quotation_contract_fixtures.dart';
import '../../../support/quotation_harness.dart';

void main() {
  late QuotationHarness h;
  late GuardarCotizacionCommand save;
  late RecuperarCotizacionCommand recovery;
  setUp(() async {
    h = QuotationHarness();
    final catalog = quotationFixture('catalogo-inicial');
    for (final row in catalog['inventory_items'] as List) {
      await h.db
          .into(h.db.inventoryItems)
          .insert(
            InventoryItemsCompanion.insert(
              id: row['id'] as String,
              name: row['name'] as String,
              defaultUnitId: row['default_unit_id'] as String,
            ),
          );
    }
    for (final row in catalog['products'] as List) {
      await h.db
          .into(h.db.products)
          .insert(
            ProductsCompanion.insert(
              id: row['id'] as String,
              name: row['name'] as String,
              saleMode: Value(row['sale_mode'] as String),
              saleUnitId: Value(row['sale_unit_id'] as String?),
              priceReferenceQuantityAtomic: Value(
                row['price_reference_quantity_atomic'] as int?,
              ),
            ),
          );
    }
    for (final row in catalog['product_variants'] as List) {
      await h.db
          .into(h.db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: row['id'] as String,
              productId: row['product_id'] as String,
              name: Value(row['name'] as String?),
              nameKey: Value((row['name'] as String?)?.toLowerCase()),
              salePriceMinor: row['sale_price_minor'] as int,
              standardCostMinor: Value(row['standard_cost_minor'] as int?),
              inventoryItemId: Value(row['inventory_item_id'] as String?),
              sortOrder: row['sort_order'] as int,
            ),
          );
    }
    final json = quotationFixture('seleccion-sin-precios');
    final payload = CotizacionGuardadaPayload.fromJson(json);
    for (var i = 0; i < payload.lines.length; i++) {
      final line = payload.lines[i], s = line.selection;
      final prepared = await h.products.findVariantById(s.variantId);
      final snapshot = SaleItemSnapshot(
        variantId: s.variantId,
        consumptionConfigurationKey: await h.products
            .consumptionConfigurationKey(s.variantId),
        productName: s.productName,
        variantName: s.variantName,
        saleMode: s.saleMode,
        quantity: s.quantity,
        measuredQuantityAtomic: s.measuredQuantityAtomic,
        unitPriceMinor: prepared!.precioVentaMenor,
        standardCostMinor: prepared.costoEstandarMenor,
        priceReferenceQuantityAtomic: s.saleMode == 'measured' ? 1 : null,
        unitCode: s.unitCode,
        unitSymbol: s.unitSymbol,
        unitAtomicFactor: s.unitAtomicFactor,
      );
      await h.events.appendAndApply(
        SyncEvent(
          eventId: i == 1
              ? payload.sourceDraftEventId
              : '20000000-0000-4000-8000-000000000030',
          aggregateType: 'sale_draft',
          aggregateId: payload.sourceSaleId,
          eventType: ProductoAgregadoBorradorPayload.eventType,
          userId: h.context.userId,
          deviceId: h.context.deviceId,
          baseVersion: i,
          createdAtLocal: DateTime.utc(2026, 10, 6, 17),
          deliveryStatus: 'not_required',
          payload: ProductoAgregadoBorradorPayload(
            saleItemId: line.sourceSaleItemId,
            sortOrder: line.sortOrder,
            item: snapshot,
          ).toJson(),
        ),
        refs: [
          LocalEventRef.affects(refType: 'sale', refId: payload.sourceSaleId),
        ],
      );
    }
    final e = quotationFixture('guardado-evento-v2')['event'] as Map;
    save = GuardarCotizacionCommand(
      saleId: payload.sourceSaleId,
      expectedDraftEventId: payload.sourceDraftEventId,
      quotationId: e['aggregate_id'] as String,
      eventId: e['event_id'] as String,
      issuedAtLocal: DateTime.fromMillisecondsSinceEpoch(
        payload.issuedAtMs,
        isUtc: true,
      ),
    );
    await h.service().guardar(save);
    await h.drafts.limpiar(LimpiarVentaBorradorCommand(saleId: save.saleId));
    final link = quotationFixture('recuperacion-vinculo-v2')['event'] as Map;
    final p = CotizacionRecuperadaPayload.fromJson(
      link['payload'] as Map<String, Object?>,
    );
    recovery = RecuperarCotizacionCommand(
      quotationId: save.quotationId,
      expectedQuotationEventId: save.eventId,
      saleId: p.saleId,
      eventId: link['event_id'] as String,
      recoveredAtLocal: DateTime.fromMillisecondsSinceEpoch(
        p.recoveredAtMs,
        isUtc: true,
      ),
    );
  });
  tearDown(() => h.dispose());
  Future<void> updateCatalog() async {
    final c = quotationFixture('catalogo-actualizado');
    for (final row in c['products'] as List) {
      await (h.db.update(
        h.db.products,
      )..where((t) => t.id.equals(row['id'] as String))).write(
        ProductsCompanion(
          name: Value(row['name'] as String),
          priceReferenceQuantityAtomic: Value(
            row['price_reference_quantity_atomic'] as int?,
          ),
        ),
      );
    }
    for (final row in c['product_variants'] as List) {
      await (h.db.update(
        h.db.productVariants,
      )..where((t) => t.id.equals(row['id'] as String))).write(
        ProductVariantsCompanion(
          name: Value(row['name'] as String?),
          nameKey: Value((row['name'] as String?)?.toLowerCase()),
          salePriceMinor: Value(row['sale_price_minor'] as int),
          standardCostMinor: Value(row['standard_cost_minor'] as int?),
          inventoryItemId: Value(row['inventory_item_id'] as String?),
        ),
      );
    }
  }

  void noQuotationMoney(Object? value) {
    const forbidden = {
      'currency',
      'total_minor',
      'unit_price_minor',
      'standard_cost_minor_snapshot',
      'price_reference_quantity_atomic_snapshot',
      'consumption_configuration_key',
      'catalog_unit_price_minor',
      'snapshot',
    };
    if (value is Map) {
      expect(value.keys.where(forbidden.contains), isEmpty);
      for (final child in value.values) {
        noQuotationMoney(child);
      }
    }
    if (value is List) {
      for (final child in value) {
        noQuotationMoney(child);
      }
    }
  }

  for (final mode in AppMode.values) {
    test(
      'P01/P02/P03/P06/P07/P10/P12/P23/P24: fixtures reales sin importes quotation, venta vigente $mode',
      () async {
        h.config.update(h.config.config.copyWith(mode: mode));
        expect(
          (await h.db.quotationDao.findEventById(save.eventId))!.payload,
          quotationFixture('seleccion-sin-precios'),
        );
        final schema = quotationFixture('esquema-compatibilidad');
        for (final entry in (schema['required_columns'] as Map).entries) {
          final columns = await h.db
              .customSelect('PRAGMA table_info(${entry.key})')
              .get();
          final names = columns.map((r) => r.data['name']).toSet();
          expect(
            names.containsAll((entry.value as List).cast<String>()),
            isTrue,
          );
          expect(
            names.intersection(
              ((schema['forbidden_columns'] as Map)[entry.key] as List)
                  .cast<String>()
                  .toSet(),
            ),
            isEmpty,
          );
          final ddl =
              (await h.db
                          .customSelect(
                            "SELECT sql FROM sqlite_master WHERE name='${entry.key}'",
                          )
                          .get())
                      .single
                      .data['sql']
                  as String;
          for (final field
              in (schema['forbidden_columns'] as Map)[entry.key] as List) {
            expect(ddl, isNot(contains(field)));
          }
        }
        await updateCatalog();
        final document = (await h.repository.findById(save.quotationId))!;
        final beforeRead = await h.contents();
        final estimate = await h.repository.estimate(document);
        expect(estimate.lines.map((l) => l.totalMinor), [24000, 15000]);
        expect(estimate.totalMinor, 39000);
        expect(QuotationDisplay(document, estimate).total, r'$390.00 MXN');
        expect(await h.contents(), beforeRead);
        final before = await h.contents(
          excluded: {
            'sales',
            'sale_items',
            'events',
            'event_refs',
            'quotations',
          },
        );
        final eventsBefore = (await h.db.select(h.db.events).get()).length;
        final refsBefore = (await h.db.select(h.db.eventRefs).get()).length;
        await h.service().recuperar(recovery);
        expect(
          await h.contents(
            excluded: {
              'sales',
              'sale_items',
              'events',
              'event_refs',
              'quotations',
            },
          ),
          before,
        );
        expect((await h.db.select(h.db.events).get()).length - eventsBefore, 3);
        expect(
          (await h.db.select(h.db.eventRefs).get()).length - refsBefore,
          mode == AppMode.serverSync ? 13 : 0,
        );
        final expected = quotationFixture('recuperacion-esperada');
        final sale = (await h.db.saleDao.findById(recovery.saleId))!;
        expect(sale.version, 2);
        expect(sale.totalMinor, 39000);
        expect(
          sale.createdEventId,
          (expected['sale'] as Map)['created_event_id'],
        );
        expect(sale.lastEventId, (expected['sale'] as Map)['last_event_id']);
        final lines = await h.db.saleDao.items(sale.id);
        for (var i = 0; i < lines.length; i++) {
          final row = (expected['sale_items'] as List)[i] as Map;
          for (final entry in lines[i].snapshot.toJson().entries) {
            expect(row[entry.key], entry.value, reason: entry.key);
          }
          expect(lines[i].id, row['id']);
          expect(lines[i].snapshot.totalMinor, row['total_minor']);
        }
        expect(
          (await h.db.quotationDao.findEventById(recovery.eventId))!.payload,
          (quotationFixture('recuperacion-vinculo-v2')['event']
              as Map)['payload'],
        );
        for (final row in await (h.db.select(
          h.db.events,
        )..where((t) => t.aggregateType.equals('quotation'))).get()) {
          noQuotationMoney(jsonDecode(row.payload));
        }
        for (final row in await h.db.select(h.db.events).get()) {
          expect(row.deliveryStatus, 'not_required');
        }
        expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
        final evidencePath =
            Platform.environment['POS_QUOTATION_CORE_EVIDENCE'];
        if (evidencePath != null) {
          final output = Directory(evidencePath);
          await output.create(recursive: true);
          final result = {
            'mode': mode.name,
            'schema_version': h.db.schemaVersion,
            'schema': {
              for (final table in ['quotations', 'quotation_items'])
                table:
                    (await h.db.customSelect('PRAGMA table_info($table)').get())
                        .map((row) => row.data)
                        .toList(),
            },
            'ddl':
                (await h.db
                        .customSelect(
                          "SELECT name,sql FROM sqlite_master WHERE name IN ('quotations','quotation_items')",
                        )
                        .get())
                    .map((row) => row.data)
                    .toList(),
            'quotation_events':
                (await (h.db.select(
                      h.db.events,
                    )..where((t) => t.aggregateType.equals('quotation'))).get())
                    .map(
                      (row) => {
                        'event_id': row.eventId,
                        'payload': jsonDecode(row.payload),
                      },
                    )
                    .toList(),
            'sale_version': sale.version,
            'sale_created_event': sale.createdEventId,
            'sale_last_event': sale.lastEventId,
            'sale_total_minor': sale.totalMinor,
            'sale_items': [
              for (final line in lines)
                {
                  'id': line.id,
                  ...line.snapshot.toJson(),
                  'total_minor': line.snapshot.totalMinor,
                },
            ],
            'new_event_count': 3,
            'new_ref_count':
                (await h.db.select(h.db.eventRefs).get()).length - refsBefore,
          };
          await File(
            '${output.path}/fase-2-sqlite-${mode.name}.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
        }
      },
    );
  }
  test(
    'P09/P10: estimación incompleta conserva todas las líneas y no presenta suma parcial',
    () async {
      await updateCatalog();
      await (h.db.update(h.db.productVariants)
            ..where((t) => t.id.equals('20000000-0000-4000-8000-000000000010')))
          .write(const ProductVariantsCompanion(active: Value(false)));
      final before = await h.contents();
      final q = (await h.repository.findById(save.quotationId))!;
      final estimate = await h.repository.estimate(q);
      expect(estimate.totalMinor, isNull);
      expect(estimate.lines, hasLength(2));
      expect(estimate.lines.first.totalMinor, 24000);
      expect(estimate.lines.last.unitPriceMinor, isNull);
      expect(estimate.lines.last.issue, isNotEmpty);
      final display = QuotationDisplay(q, estimate);
      expect(display.total, 'Total no disponible');
      expect(display.itemRows.last.last, 'Importe no disponible');
      await expectLater(h.service().recuperar(recovery), throwsA(anything));
      expect(await h.contents(), before);
    },
  );
  test(
    'P14/P15/P16/P17: edición conservada, limpiar permite otro precio, replay no resucita ni regresa vínculo',
    () async {
      await updateCatalog();
      await h.service().recuperar(recovery);
      final old = (await h.db.quotationDao.findEventById(recovery.eventId))!;
      final saleEvents = await (h.db.select(
        h.db.events,
      )..where((t) => t.aggregateId.equals(recovery.saleId))).get();
      final line = (await h.db.saleDao.items(recovery.saleId)).first;
      await h.drafts.actualizarProducto(
        ActualizarProductoBorradorCommand(saleItemId: line.id, quantity: 3),
      );
      await (h.db.update(h.db.productVariants)
            ..where((t) => t.id.equals(line.snapshot.variantId)))
          .write(const ProductVariantsCompanion(salePriceMinor: Value(13000)));
      final before = await h.contents();
      expect((await h.service().recuperar(recovery)).continued, isTrue);
      expect(
        (await h.db.saleDao.items(
          recovery.saleId,
        )).first.snapshot.unitPriceMinor,
        12000,
      );
      expect(await h.contents(), before);
      await h.drafts.limpiar(
        LimpiarVentaBorradorCommand(saleId: recovery.saleId),
      );
      final second = RecuperarCotizacionCommand(
        quotationId: save.quotationId,
        expectedQuotationEventId: recovery.eventId,
      );
      await h.service().recuperar(second);
      expect(
        (await h.db.saleDao.items(second.saleId)).first.snapshot.unitPriceMinor,
        13000,
      );
      final newer = await h.contents();
      await h.recoveryHandler.apply(old);
      for (final row in saleEvents) {
        await VentaBorradorEventHandler(
          h.db.saleDao,
        ).apply((await h.db.quotationDao.findEventById(row.eventId))!);
      }
      expect((await h.service().recuperar(recovery)).draftAvailable, isFalse);
      expect(await h.contents(), newer);
    },
  );
  for (final failure in ['draftEvent', 'draftRefs', 'linkEvent', 'linkRefs']) {
    test('P13: rollback integral y secuencia estable al fallar $failure', () async {
      h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
      await updateCatalog();
      final sql = switch (failure) {
        'draftEvent' =>
          "CREATE TRIGGER injected BEFORE INSERT ON events WHEN NEW.event_type='producto_agregado_borrador' AND NEW.base_version=1 BEGIN SELECT RAISE(ABORT,'line'); END",
        'draftRefs' =>
          "CREATE TRIGGER injected BEFORE INSERT ON event_refs WHEN NEW.ref_type='unit' BEGIN SELECT RAISE(ABORT,'refs'); END",
        'linkEvent' =>
          "CREATE TRIGGER injected BEFORE INSERT ON events WHEN NEW.event_type='cotizacion_recuperada' BEGIN SELECT RAISE(ABORT,'link'); END",
        _ =>
          "CREATE TRIGGER injected BEFORE INSERT ON event_refs WHEN NEW.ref_type='event' BEGIN SELECT RAISE(ABORT,'refs'); END",
      };
      await h.db.customStatement(sql);
      final before = await h.contents();
      await expectLater(h.service().recuperar(recovery), throwsA(anything));
      expect(await h.contents(), before);
      await h.db.customStatement('DROP TRIGGER injected');
      await h.service().recuperar(recovery);
      expect((await h.db.saleDao.findById(recovery.saleId))!.totalMinor, 39000);
    });
  }
}
