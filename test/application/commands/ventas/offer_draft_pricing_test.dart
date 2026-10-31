import 'package:pos_flutter/presentation/pages/caja/models/sale_receipt_display.dart';
import 'package:pos_flutter/presentation/pages/informes/models/sales_reports_calculator.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import 'package:pos_flutter/application/commands/ventas/prepare_sale_adjustment.dart';
import 'package:pos_flutter/data/repositories/sale_adjustment_repository_impl.dart';
import '../../../support/sale_adjustment_harness.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/ventas/cambiar_tarifa_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/actualizar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/handlers/tarifa_venta_borrador_cambiada_event_handler.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/application/sync/payloads/sale_item_snapshot.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import '../../../support/quotation_harness.dart';

const uuid = Uuid();
const direct = QuotationHarness.directId;
const measured = QuotationHarness.measuredId;

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late QuotationHarness h;
      setUp(() async {
        h = QuotationHarness(mode: mode);
        await h.seed();
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(direct))).write(
          const ProductVariantsCompanion(offerPriceMinor: Value(2000)),
        );
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(measured))).write(
          const ProductVariantsCompanion(
            salePriceMinor: Value(5000),
            offerPriceMinor: Value(4000),
          ),
        );
      });
      tearDown(() => h.dispose());
      Future<SaleRow> sale() async =>
          (await h.db.select(h.db.sales).get()).single;
      Future<CambiarTarifaVentaBorradorCommand> intent([
        String mode = 'offer',
      ]) async {
        final s = await sale();
        return CambiarTarifaVentaBorradorCommand(
          operationId: uuid.v4(),
          saleId: s.id,
          pricingMode: mode,
          expectedVersion: s.version,
          expectedDraftEventId: s.lastEventId,
          expectedTotalMinor: s.totalMinor,
        );
      }

      Future<void> toggle([String mode = 'offer']) async =>
          h.drafts.cambiarTarifa(await intent(mode));
      Future<void> capture(String id, {int? amount, String? quantity}) async {
        final c = await h.drafts.prepararCaptura(id);
        await h.drafts.agregar(
          c.bind(
            AgregarProductoBorradorCommand(
              variantId: id,
              targetAmountMinor: amount,
              measuredQuantity: quantity,
              expectedUnitId: c.measured?.unit.id,
              expectedUnitPriceMinor: c.measured?.unitPriceMinor,
              expectedPriceReferenceQuantityAtomic:
                  c.measured?.priceReferenceQuantityAtomic,
            ),
          ),
        );
      }

      test('vacía durable, agregado posterior y refs por modo', () async {
        final id = uuid.v4();
        final result = await h.drafts.cambiarTarifa(
          CambiarTarifaVentaBorradorCommand(
            operationId: uuid.v4(),
            saleId: id,
            pricingMode: 'offer',
            expectedVersion: 0,
            expectedDraftEventId: null,
            expectedTotalMinor: 0,
          ),
        );
        expect(result!.totalMinor, 0);
        expect((await sale()).pricingMode, 'offer');
        await h.add();
        expect((await sale()).id, id);
        expect((await sale()).totalMinor, 2000);
        expect(
          (await h.db.saleDao.items(id)).single.snapshot.effectivePriceSource,
          'offer',
        );
        expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
        final refs = await h.db.select(h.db.eventRefs).get();
        expect(refs.isEmpty, mode == AppMode.standalone);
      });
      test(
        'mezcla, preview sin escribir, activar/desactivar y costo intacto',
        () async {
          await h.add();
          await h.add();
          await h.add(QuotationHarness.recipeId);
          final before = await h.contents();
          final c = await intent();
          final preview = await h.drafts.previewTarifa(c);
          expect(await h.contents(), before);
          expect(preview.previousTotalMinor, 9400);
          expect(preview.totalMinor, 6400);
          expect(preview.amountChangedLines, 1);
          expect(preview.withoutOfferLines, 1);
          await h.drafts.cambiarTarifa(c);
          final lines = await h.db.saleDao.items((await sale()).id);
          expect(lines.map((l) => l.snapshot.standardCostMinor), [900, 900]);
          expect(lines.map((l) => l.snapshot.effectivePriceSource), [
            'offer',
            'normal',
          ]);
          expect(lines.map((l) => l.id), preview.lines.map((l) => l.id));
          await toggle('normal');
          expect((await sale()).totalMinor, 9400);
          expect(await h.db.select(h.db.inventoryMovements).get(), isEmpty);
        },
      );
      test('oferta igual conserva origen explícito y revisión', () async {
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(direct))).write(
          const ProductVariantsCompanion(offerPriceMinor: Value(3500)),
        );
        await h.add();
        final b = await sale();
        await toggle();
        final a = await sale();
        expect(a.totalMinor, b.totalMinor);
        expect(a.version, b.version + 1);
        expect(
          (await h.db.saleDao.items(a.id)).single.snapshot.effectivePriceSource,
          'offer',
        );
      });
      test(
        'catálogo posterior no refresca, nuevas capturas separan condiciones',
        () async {
          await h.add();
          final id = (await sale()).id;
          await h.db
              .update(h.db.productVariants)
              .write(
                const ProductVariantsCompanion(
                  salePriceMinor: Value(6000),
                  offerPriceMinor: Value(null),
                  lastEventId: Value('00000000-0000-4000-8000-000000000099'),
                ),
              );
          await toggle();
          expect((await sale()).totalMinor, 2000);
          await h.add();
          expect((await h.db.saleDao.items(id)), hasLength(2));
          await toggle('normal');
          expect((await sale()).totalMinor, 9500);
          final lines = await h.db.saleDao.items(id);
          await h.drafts.actualizarProducto(
            ActualizarProductoBorradorCommand(
              saleItemId: lines.first.id,
              quantity: 3,
            ),
          );
          expect((await sale()).totalMinor, 16500);
          expect(
            (await h.db.saleDao.items(
              id,
            )).first.snapshot.normalPriceMinorSnapshot,
            3500,
          );
        },
      );
      test('peso e importe conservan cantidad física y redondeo', () async {
        await capture(measured, quantity: '0.700');
        expect((await sale()).totalMinor, 3500);
        await toggle();
        expect((await sale()).totalMinor, 2800);
        await capture(measured, amount: 1000);
        final line = (await h.db.saleDao.items((await sale()).id)).single;
        expect(line.snapshot.measuredQuantityAtomic, 950);
        expect(line.snapshot.totalMinor, 3800);
        await toggle('normal');
        expect((await sale()).totalMinor, 4750);
        expect(
          (await h.db.saleDao.items(
            (await sale()).id,
          )).single.snapshot.measuredQuantityAtomic,
          950,
        );
      });
      test('importe nuevo usa oferta: 250 g / desactivar 1250', () async {
        await h.drafts.cambiarTarifa(
          CambiarTarifaVentaBorradorCommand(
            operationId: uuid.v4(),
            saleId: uuid.v4(),
            pricingMode: 'offer',
            expectedVersion: 0,
            expectedDraftEventId: null,
            expectedTotalMinor: 0,
          ),
        );
        await capture(measured, amount: 1000);
        expect((await sale()).totalMinor, 1000);
        expect(
          (await h.db.saleDao.items(
            (await sale()).id,
          )).single.snapshot.measuredQuantityAtomic,
          250,
        );
        await toggle('normal');
        expect((await sale()).totalMinor, 1250);
      });
      for (final change in ['mode', 'revision', 'catalog', 'tab']) {
        test(
          'captura iniciada rechaza cambio $change antes de escribir',
          () async {
            await h.add();
            final repo = SaleDraftRepositoryImpl(
              saleDao: h.db.saleDao,
              userId: h.context.userId,
              deviceId: h.context.deviceId,
            );
            repo.selectDraft((await sale()).id);
            final service = VentaBorradorCommandService(
              store: h.db.saleDao,
              products: h.products,
              units: UnidadInventarioRepositoryImpl(unitDao: h.db.unitDao),
              events: h.events,
              context: h.context,
              drafts: repo,
            );
            final c = await service.prepararCaptura(direct);
            if (change == 'mode') await toggle();
            if (change == 'revision') await h.add();
            if (change == 'catalog') {
              await h.db
                  .update(h.db.productVariants)
                  .write(
                    ProductVariantsCompanion(lastEventId: Value(uuid.v4())),
                  );
            }
            if (change == 'tab') repo.selectDraft(uuid.v4());
            final before = await h.contents();
            await expectLater(
              service.agregar(
                c.bind(const AgregarProductoBorradorCommand(variantId: direct)),
              ),
              throwsStateError,
            );
            expect(await h.contents(), before);
          },
        );
      }
      test(
        'reintento después de editar y limpiar devuelve resultado original; identidad distinta rechaza',
        () async {
          await h.add();
          final c = await intent();
          final first = await h.drafts.cambiarTarifa(c);
          await h.add();
          expect((await h.drafts.cambiarTarifa(c))!.toJson(), first!.toJson());
          await expectLater(
            h.drafts.cambiarTarifa(
              CambiarTarifaVentaBorradorCommand(
                operationId: c.operationId,
                saleId: c.saleId,
                pricingMode: 'normal',
                expectedVersion: c.expectedVersion,
                expectedDraftEventId: c.expectedDraftEventId,
                expectedTotalMinor: c.expectedTotalMinor,
              ),
            ),
            throwsStateError,
          );
          final applied = await h.db.saleDao.appliedLocalEvent(c.operationId);
          await h.drafts.limpiar(LimpiarVentaBorradorCommand(saleId: c.saleId));
          await TarifaVentaBorradorCambiadaEventHandler(
            h.db.saleDao,
          ).apply(applied!);
          expect((await h.drafts.cambiarTarifa(c))!.toJson(), first.toJson());
          expect(await h.db.saleDao.findById(c.saleId), isNull);
        },
      );
      for (final target in ['item', 'sale', 'event', 'refs']) {
        test('fallo SQL $target rollback completo y reintento una vez', () async {
          if (target == 'refs' && mode == AppMode.standalone) return;
          await h.add();
          await h.add(QuotationHarness.recipeId);
          final c = await intent();
          final before = await h.contents();
          final sql = switch (target) {
            'item' => "BEFORE UPDATE ON sale_items WHEN OLD.sort_order=1",
            'sale' => "BEFORE UPDATE ON sales",
            'event' =>
              "BEFORE UPDATE ON events WHEN OLD.event_type='tarifa_venta_borrador_cambiada'",
            _ => "BEFORE INSERT ON event_refs",
          };
          await h.db.customStatement(
            "CREATE TRIGGER fail_pricing $sql BEGIN SELECT RAISE(ABORT,'injected pricing'); END",
          );
          await expectLater(h.drafts.cambiarTarifa(c), throwsA(anything));
          expect(await h.contents(), before);
          await h.db.customStatement('DROP TRIGGER fail_pricing');
          await h.drafts.cambiarTarifa(c);
          await h.drafts.cambiarTarifa(c);
          expect((await sale()).version, c.expectedVersion + 1);
          expect(
            (await h.db.select(h.db.events).get()).where(
              (e) => e.eventId == c.operationId,
            ),
            hasLength(1),
          );
        });
      }
      test(
        'legado conserva importes, bloquea toggle y cobra venta mixta',
        () async {
          await h.add();
          await h.db.customStatement(
            'UPDATE sale_items SET price_snapshot_version=NULL, normal_price_minor_snapshot=NULL, offer_price_minor_snapshot=NULL, effective_price_source=NULL, price_selection=NULL, price_configuration_event_id=NULL',
          );
          final before = await h.contents();
          await expectLater(toggle(), throwsStateError);
          expect(await h.contents(), before);
          await h.add(QuotationHarness.recipeId);
          await h.confirm();
          final e = (await h.db.select(h.db.events).get()).last;
          final p = VentaConfirmadaPayload.fromJson(
            Map<String, Object?>.from(jsonDecode(e.payload) as Map),
          );
          expect(p.lines.first.snapshot.priceSnapshotVersion, isNull);
          expect(p.lines.last.snapshot.priceSnapshotVersion, 2);
        },
      );
      for (final method in ['cash', 'transfer', 'credit']) {
        test(
          'cobro $method conserva precio y evento histórico separado de consumo',
          () async {
            final customer = method == 'credit' ? await h.customer() : null;
            await h.add();
            await toggle();
            await h.db
                .update(h.db.productVariants)
                .write(
                  ProductVariantsCompanion(
                    lastEventId: Value(uuid.v4()),
                    salePriceMinor: const Value(9000),
                  ),
                );
            await h.confirm(method: method, clienteId: customer);
            final e = (await h.db.select(h.db.events).get()).last;
            final event = await h.db.saleDao.appliedLocalEvent(e.eventId);
            final p = VentaConfirmadaPayload.fromJson(event!.payload);
            expect(p.totalMinor, 2000);
            expect(p.pricingMode, 'offer');
            expect(
              p.lines.single.configurationEventId,
              isNot(p.lines.single.snapshot.priceConfigurationEventId),
            );
            expect(
              p.dependencyEventIds,
              contains(p.lines.single.snapshot.priceConfigurationEventId),
            );
            final read = ConfirmedSaleRepositoryImpl.fromEvent(event);
            expect(read.items.single.unitPriceMinor, 2000);
            expect(read.items.single.standardCostMinor, 900);
            expect(read.items.single.effectivePriceOrigin, 'offer');
            expect(read.effectivePricingMode, 'offer');
            final period = ReportPeriod.day(read.createdAt);
            expect(
              SalesReportsCalculator.ventasTotales(period, [read]),
              BigInt.from(2000),
            );
            expect(
              SalesReportsCalculator.grossProfit(period, [read]).profitMinor,
              BigInt.from(1100),
            );
            expect(
              SaleReceiptDisplay(read).ticket.itemRows.single.last,
              r'$20.00',
            );
            expect(
              (await h.db.select(h.db.inventoryMovements).get())
                  .single
                  .quantityDeltaAtomic,
              -1,
            );
          },
        );
      }
      for (final first in ['pricing', 'payment']) {
        test(
          'carrera $first primero: solo un ganador usando la misma revisión',
          () async {
            await h.add();
            final c = await intent();
            final s = await sale();
            final pay = VentaCommandService(
              drafts: h.db.saleDao,
              products: h.products,
              events: h.events,
              context: h.context,
              inventory: DriftInventoryProjectionStore(
                inventoryDao: h.db.inventoryDao,
                unitDao: h.db.unitDao,
              ),
            );
            Future<Object?> payment() => pay.confirmar(
              ConfirmarVentaCommand(
                saleId: s.id,
                expectedDraftEventId: s.lastEventId!,
                expectedVersion: s.version,
                expectedTotalMinor: s.totalMinor,
              ),
            );
            Future<Object?> pricing() => h.drafts.cambiarTarifa(c);
            Future<bool> run(Future<Object?> Function() f) async {
              try {
                await f();
                return true;
              } on StateError {
                return false;
              }
            }

            final results = await Future.wait(
              first == 'pricing'
                  ? [run(pricing), run(payment)]
                  : [run(payment), run(pricing)],
            );
            expect(results, [true, false]);
            expect(
              (await sale()).status,
              first == 'payment' ? 'confirmada' : 'borrador',
            );
          },
        );
      }
      for (final voidSale in [false, true]) {
        test(
          'ajuste histórico ${voidSale ? 'anulación' : 'devoluciones sucesivas'} usa cobro original',
          () async {
            await h.add();
            await h.add();
            await toggle();
            await h.confirm();
            final original = await sale();
            final line = (await h.db.saleDao.items(original.id)).single;
            await h.db
                .update(h.db.productVariants)
                .write(
                  const ProductVariantsCompanion(
                    salePriceMinor: Value(9000),
                    offerPriceMinor: Value(100),
                    standardCostMinor: Value(8000),
                    active: Value(false),
                  ),
                );
            final dir = await Directory.systemTemp.createTemp(
              'pricing_adjustment_',
            );
            final adjustments = SaleAdjustmentHarness(h.db, dir);
            try {
              final prepare = PrepareSaleAdjustment(
                adjustments.service(),
                adjustments.cashStore,
              );
              var sum = 0;
              for (var i = 0; i < (voidSale ? 1 : 2); i++) {
                final payload = await prepare.call(
                  saleId: original.id,
                  expectedRevision: i,
                  voidSale: voidSale,
                  reason: 'Devolución de prueba',
                  action: 'refund_completed',
                  selections: {line.id: (quantity: 1, destination: 'restock')},
                );
                sum += payload.totalMinor;
                await adjustments.execute(payload.toJson());
              }
              expect(sum, 4000);
              final history = (await SaleAdjustmentRepositoryImpl(
                h.db,
              ).watchSales().first).single;
              expect(history.original.totalMinor, 4000);
              expect(
                history.original.items.single.effectivePriceOrigin,
                'offer',
              );
              expect(history.original.items.single.standardCostMinor, 900);
              expect(
                (await h.db.saleDao.findById(original.id))!.totalMinor,
                4000,
              );
            } finally {
              adjustments.config.dispose();
              await dir.delete(recursive: true);
            }
          },
        );
      }
      test(
        'límite de línea al desactivar revierte toda la operación',
        () async {
          await (h.db.update(
            h.db.productVariants,
          )..where((t) => t.id.equals(direct))).write(
            const ProductVariantsCompanion(
              salePriceMinor: Value(SaleItemSnapshot.maxInteger),
              offerPriceMinor: Value(1),
            ),
          );
          await h.drafts.cambiarTarifa(
            CambiarTarifaVentaBorradorCommand(
              operationId: uuid.v4(),
              saleId: uuid.v4(),
              pricingMode: 'offer',
              expectedVersion: 0,
              expectedDraftEventId: null,
              expectedTotalMinor: 0,
            ),
          );
          await h.add();
          await h.add();
          final c = await intent('normal');
          final before = await h.contents();
          await expectLater(h.drafts.cambiarTarifa(c), throwsFormatException);
          expect(await h.contents(), before);
        },
      );
      test('importe ceil, half-up y cero medido usan enteros', () async {
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(measured))).write(
          const ProductVariantsCompanion(
            salePriceMinor: Value(300),
            offerPriceMinor: Value(null),
          ),
        );
        await (h.db.update(
          h.db.products,
        )..where((t) => t.id.equals(QuotationHarness.measuredProductId))).write(
          const ProductsCompanion(priceReferenceQuantityAtomic: Value(10)),
        );
        await capture(measured, amount: 100);
        var line = (await h.db.saleDao.items((await sale()).id)).single;
        expect(line.snapshot.measuredQuantityAtomic, 4);
        expect(line.snapshot.totalMinor, 120);
        await h.drafts.limpiar(
          LimpiarVentaBorradorCommand(saleId: (await sale()).id),
        );
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(measured))).write(
          const ProductVariantsCompanion(
            salePriceMinor: Value(1),
            offerPriceMinor: Value(null),
          ),
        );
        await (h.db.update(
          h.db.products,
        )..where((t) => t.id.equals(QuotationHarness.measuredProductId))).write(
          const ProductsCompanion(priceReferenceQuantityAtomic: Value(2)),
        );
        await capture(measured, quantity: '0.001');
        expect((await sale()).totalMinor, 1);
      });
      test(
        'retry y replay después del cobro no reabren ni cobran otra vez',
        () async {
          await h.add();
          final c = await intent();
          final result = await h.drafts.cambiarTarifa(c);
          final event = await h.db.saleDao.appliedLocalEvent(c.operationId);
          await h.confirm();
          final before = await h.contents();
          expect((await h.drafts.cambiarTarifa(c))!.toJson(), result!.toJson());
          await TarifaVentaBorradorCambiadaEventHandler(
            h.db.saleDao,
          ).apply(event!);
          expect(await h.contents(), before);
        },
      );
      test(
        'evento ajeno con versión antigua no se considera aplicado por versión',
        () async {
          await h.add();
          final c = await intent();
          await h.drafts.cambiarTarifa(c);
          final e = (await h.db.saleDao.appliedLocalEvent(c.operationId))!;
          await h.add();
          final before = await h.contents();
          await expectLater(
            TarifaVentaBorradorCambiadaEventHandler(
              h.db.saleDao,
            ).apply(e.copyWith(eventId: uuid.v4())),
            throwsStateError,
          );
          expect(await h.contents(), before);
        },
      );
      test(
        'no-op no genera evento y revisión obsoleta rechaza aunque total igual',
        () async {
          await h.add();
          final c = await intent('normal');
          final before = await h.contents();
          expect(await h.drafts.cambiarTarifa(c), isNull);
          expect(await h.contents(), before);
          await toggle();
          await toggle('normal');
          await expectLater(h.drafts.cambiarTarifa(c), throwsStateError);
        },
      );
      test(
        'catálogo sin evento rechaza captura sin fabricar historia',
        () async {
          await h.db
              .update(h.db.productVariants)
              .write(
                const ProductVariantsCompanion(
                  createdEventId: Value(null),
                  lastEventId: Value(null),
                ),
              );
          final before = await h.contents();
          await expectLater(h.add(), throwsStateError);
          expect(await h.contents(), before);
        },
      );
    });
  }
  test(
    'reapertura real conserva tarifa, aislamiento y venta nueva normal',
    () async {
      final dir = await Directory.systemTemp.createTemp('offer_pricing_');
      final file = File('${dir.path}/test.sqlite');
      var h = QuotationHarness(
        database: AppDatabase.forTesting(NativeDatabase(file)),
      );
      await h.seed();
      await h.add();
      final s = (await h.db.select(h.db.sales).get()).single;
      await h.drafts.cambiarTarifa(
        CambiarTarifaVentaBorradorCommand(
          operationId: uuid.v4(),
          saleId: s.id,
          pricingMode: 'offer',
          expectedVersion: s.version,
          expectedDraftEventId: s.lastEventId,
          expectedTotalMinor: s.totalMinor,
        ),
      );
      await h.dispose();
      h = QuotationHarness(
        database: AppDatabase.forTesting(NativeDatabase(file)),
      );
      try {
        expect((await h.db.saleDao.findById(s.id))!.pricingMode, 'offer');
        final repo = SaleDraftRepositoryImpl(
          saleDao: h.db.saleDao,
          userId: h.context.userId,
          deviceId: h.context.deviceId,
        );
        repo.selectDraft(uuid.v4());
        final service = VentaBorradorCommandService(
          store: h.db.saleDao,
          products: h.products,
          events: h.events,
          context: h.context,
          units: UnidadInventarioRepositoryImpl(unitDao: h.db.unitDao),
          drafts: repo,
        );
        await service.agregar(
          const AgregarProductoBorradorCommand(variantId: direct),
        );
        expect(
          (await h.db.saleDao.findById(repo.selectedDraftId!))!.pricingMode,
          'normal',
        );
        expect((await h.db.saleDao.findById(s.id))!.pricingMode, 'offer');
      } finally {
        await h.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
