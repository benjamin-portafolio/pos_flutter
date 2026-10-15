import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/application/sync/payloads/venta_confirmada_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/articulos/article_search_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/cash_payment_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/models/sale_receipt_display.dart';

import '../../../support/quotation_harness.dart';

void main() {
  for (final mode in AppMode.values) {
    testWidgets(
      'búsqueda → Caja → cobro/ticket/consumo → reapertura ${mode.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('measured-amount-'),
        ))!;
        final path = '${directory.path}/sale.sqlite';
        final harness = QuotationHarness(
          database: AppDatabase.forTesting(NativeDatabase(File(path))),
          mode: mode,
        );
        await tester.runAsync(() async {
          await harness.seed();
          await (harness.db.update(
            harness.db.productVariants,
          )..where((v) => v.id.equals(QuotationHarness.directId))).write(
            const ProductVariantsCompanion(inventoryItemId: Value(null)),
          );
          await (harness.db.update(
            harness.db.productVariants,
          )..where((v) => v.id.equals(QuotationHarness.measuredId))).write(
            const ProductVariantsCompanion(
              salePriceMinor: Value(6000),
              inventoryItemId: Value(QuotationHarness.resourceId),
            ),
          );
          await (harness.db.update(
            harness.db.inventoryItems,
          )..where((v) => v.id.equals(QuotationHarness.resourceId))).write(
            const InventoryItemsCompanion(
              defaultUnitId: Value(InventoryUnitIds.kilogram),
            ),
          );
        });
        final products = ProductoRepositoryImpl(
          productoDao: harness.db.productoDao,
        );
        final drafts = SaleDraftRepositoryImpl(
          saleDao: harness.db.saleDao,
          userId: harness.context.userId,
          deviceId: harness.context.deviceId,
        );
        final navigator = GlobalKey<NavigatorState>();
        Future<void> settle() async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
        }

        try {
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              home: ArticleSearchScreen(
                productoRepository: products,
                saleDraftRepository: drafts,
                ventaBorradorCommandService: harness.drafts,
              ),
            ),
          );
          await settle();
          for (var capture = 0; capture < 2; capture++) {
            await tester.tap(find.text('Café medido'));
            await settle();
            await tester.enterText(
              find.byKey(const ValueKey('sale-target-amount')),
              '20',
            );
            await tester.pump();
            expect(
              find.text(r'Cobro por esta cantidad: $20.04'),
              findsOneWidget,
            );
            if (capture == 1) {
              expect(
                find.text(r'Línea acumulada prevista: 0.668 kg · $40.08'),
                findsOneWidget,
              );
            }
            await tester.tap(find.text('Agregar'));
            await settle();
          }
          final draft = (await tester.runAsync(
            () => drafts.watchCurrentDraft().first,
          ))!;
          expect(draft.items.single.measuredQuantityAtomic, 668);
          expect(draft.totalMinor, 4008);
          expect(draft.items.single.consumptionConfigurationKey, isNotNull);
          expect(
            await tester.runAsync(
              () => harness.db.select(harness.db.inventoryMovements).get(),
            ),
            isEmpty,
          );
          final events = (await tester.runAsync(
            () => harness.db.select(harness.db.events).get(),
          ))!;
          final captures = events
              .where(
                (e) => e.eventType == ProductoAgregadoBorradorPayload.eventType,
              )
              .toList();
          expect(captures, hasLength(2));
          expect(
            captures.every((e) => e.deliveryStatus == 'not_required'),
            isTrue,
          );
          expect(
            await tester.runAsync(
              () => harness.db.select(harness.db.eventRefs).get(),
            ),
            hasLength(mode == AppMode.standalone ? 0 : 10),
          );
          final last = ProductoAgregadoBorradorPayload.fromJson(
            (jsonDecode(captures.last.payload) as Map).cast<String, Object?>(),
          );
          expect(last.item.measuredQuantityAtomic, 668);
          expect(last.item.totalMinor, 4008);
          unawaited(
            navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: CajaScreen(
                    saleDraftRepository: drafts,
                    productoRepository: products,
                    ventaBorradorCommandService: harness.drafts,
                    unidadInventarioRepository: UnidadInventarioRepositoryImpl(
                      unitDao: harness.db.unitDao,
                    ),
                  ),
                ),
              ),
            ),
          );
          await settle();
          expect(find.text(r'Cobrar: $40.08'), findsOneWidget);
          expect(find.textContaining('0.668 kg'), findsWidgets);
          await tester.tap(find.text(r'Cobrar: $40.08'));
          await settle();
          final payment = tester.widget<PaymentMethodScreen>(
            find.byType(PaymentMethodScreen),
          );
          expect(payment.totalMinor, 4008);
          expect(payment.saleId, draft.id);
          expect(payment.expectedDraftEventId, draft.lastEventId);
          await tester.tap(find.text('Efectivo'));
          await settle();
          final cash = tester.widget<CashPaymentScreen>(
            find.byType(CashPaymentScreen),
          );
          expect(cash.totalMinor, 4008);
          expect(cash.saleId, draft.id);
          expect(cash.expectedDraftEventId, draft.lastEventId);
          final eventId = (await tester.runAsync(() => harness.confirm()))!;
          final confirmedEvents = (await tester.runAsync(
            () =>
                (harness.db.select(harness.db.events)..where(
                      (e) =>
                          e.eventType.equals(VentaConfirmadaPayload.eventType),
                    ))
                    .get(),
          ))!;
          expect(confirmedEvents.single.eventId, eventId);
          final payload = VentaConfirmadaPayload.fromJson(
            (jsonDecode(confirmedEvents.single.payload) as Map)
                .cast<String, Object?>(),
          );
          expect(payload.totalMinor, 4008);
          expect(payload.lines.single.snapshot.measuredQuantityAtomic, 668);
          final movements = (await tester.runAsync(
            () => harness.db.select(harness.db.inventoryMovements).get(),
          ))!;
          expect(movements.single.quantityDeltaAtomic, -668);
          expect(
            (await tester.runAsync(
              () => harness.db.select(harness.db.inventoryBalances).get(),
            ))!.single.quantityOnHandAtomic,
            332,
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await settle();
          await tester.runAsync(harness.db.close);
          final reopened = AppDatabase.forTesting(NativeDatabase(File(path)));
          try {
            final sale = (await tester.runAsync(
              () => ConfirmedSaleRepositoryImpl(
                DriftConfirmedSaleStore(reopened),
              ).watchSales().first,
            ))!.single;
            expect(sale.id, draft.id);
            expect(sale.totalMinor, 4008);
            expect(sale.items.single.measuredQuantityAtomic, 668);
            final receipt = SaleReceiptDisplay(sale);
            expect(receipt.itemRows.single[2], '0.668 kg');
            expect(receipt.itemRows.single[3], r'$40.08');
            expect(
              receipt.ticket.totals,
              contains(('Total general', r'$40.08')),
            );
            expect(
              (await tester.runAsync(
                () => reopened.select(reopened.inventoryMovements).get(),
              ))!.single.quantityDeltaAtomic,
              -668,
            );
          } finally {
            await tester.runAsync(reopened.close);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 1));
          await tester.runAsync(harness.dispose);
          await tester.runAsync(() => directory.delete(recursive: true));
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
