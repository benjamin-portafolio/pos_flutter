import 'package:pos_flutter/data/repositories/transfer_summary_repository_impl.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/prepare_sale_adjustment.dart';
import 'package:pos_flutter/data/repositories/sale_adjustment_repository_impl.dart';
import 'package:pos_flutter/presentation/pages/ajustes/sale_adjustment_form_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/models/sales_reports_calculator.dart';
import 'package:pos_flutter/presentation/pages/informes/models/report_period.dart';
import '../../../support/sale_adjustment_harness.dart';

void main() {
  for (final voidSale in [true, false]) {
    testWidgets(
      'tablet ${voidSale ? 'void' : 'return'} cancel without writes',
      (tester) async {
        await tester.runAsync(() async {
          final icons = Platform.environment['POS_SESSION4_ICONS'];
          if (icons != null) {
            await (FontLoader('MaterialIcons')..addFont(
                  Future.value(
                    ByteData.sublistView(await File(icons).readAsBytes()),
                  ),
                ))
                .load();
          }
          final fontPath = Platform.environment['POS_SESSION4_FONT'];
          if (fontPath != null) {
            final loader = FontLoader('TabletQA')
              ..addFont(
                Future.value(
                  ByteData.sublistView(await File(fontPath).readAsBytes()),
                ),
              );
            await loader.load();
          }
          final h = await SaleAdjustmentHarness.create();
          addTearDown(h.close);
          final f = adjustmentFixtures().firstWhere(
            (f) =>
                f['valid'] == true &&
                object(f['payload'])['kind'] ==
                    (voidSale ? 'void' : 'return') &&
                object(object(f['payload'])['settlement'])['method'] ==
                    'cash' &&
                object(object(f['payload'])['settlement'])['cash_enabled'] ==
                    false,
          );
          await h.seed(f);
          await h.replayHistory(f);
          final sale = (await SaleAdjustmentRepositoryImpl(
            h.db,
          ).watchSales().first).single;
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(fontFamily: 'TabletQA'),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) => RepaintBoundary(
                          key: boundary,
                          child: SaleAdjustmentFormScreen(
                            sale: sale,
                            voidSale: voidSale,
                            prepare: PrepareSaleAdjustment(
                              h.service(),
                              h.cashStore,
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          );
          final before = await h.snapshot();
          await tester.tap(find.text('Abrir'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Motivo obligatorio'),
            'Error de captura',
          );
          if (!voidSale) {
            final line = sale.original.items.first;
            await tester.enterText(
              find.byKey(ValueKey('return-quantity-${line.id}')),
              '${1 / (line.unitAtomicFactor ?? 1)}',
            );
          }
          await tester.tap(find.text('Revisar consecuencias'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Importe del ajuste:'), findsOneWidget);
          expect(await h.snapshot(), before);
          expect(await h.db.select(h.db.saleAdjustmentIntents).get(), isEmpty);
          final path = Platform.environment['POS_SESSION4_VISUAL_DIR'];
          if (path != null) {
            {
              final image =
                  await (boundary.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$path/${voidSale ? 'void' : 'return'}-1280x900.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            }
          }
          await tester.ensureVisible(find.text('Cancelar'));
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          expect(await h.snapshot(), before);
          expect(await h.db.select(h.db.saleAdjustmentIntents).get(), isEmpty);
          expect(tester.takeException(), isNull);
        });
      },
    );
  }
  testWidgets(
    'A18/A25 commit fallido conserva captura e IDs; doble toque aplica una vez',
    (tester) async {
      await tester.runAsync(() async {
        final h = await SaleAdjustmentHarness.create();
        addTearDown(h.close);
        final f = adjustmentFixtures().firstWhere(
          (f) => f['name'] == 'cash_disabled_no_drawer',
        );
        await h.seed(f);
        final sale = (await SaleAdjustmentRepositoryImpl(
          h.db,
        ).watchSales().first).single;
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  child: const Text('Abrir'),
                  onPressed: () => Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => SaleAdjustmentFormScreen(
                        sale: sale,
                        voidSale: true,
                        prepare: PrepareSaleAdjustment(
                          h.service(),
                          h.cashStore,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Motivo obligatorio'),
          'Captura conservada',
        );
        await tester.tap(find.text('Revisar consecuencias'));
        await tester.pumpAndSettle();
        await h.db.customStatement(
          "CREATE TRIGGER fail_ui AFTER INSERT ON sale_adjustments BEGIN SELECT RAISE(ABORT,'injected UI failure'); END",
        );
        await tester.tap(
          find.text('Confirmo las consecuencias y la liquidación declarada.'),
        );
        await tester.pump();
        await tester.tap(find.text('Confirmar anulación'));
        await tester.pumpAndSettle();
        expect(find.text('Captura conservada'), findsOneWidget);
        expect(find.textContaining('injected UI failure'), findsOneWidget);
        expect(await h.db.select(h.db.saleAdjustments).get(), isEmpty);
        final intent =
            (await h.db.select(h.db.saleAdjustmentIntents).get()).single;
        await h.db.customStatement('DROP TRIGGER fail_ui');
        await tester.tap(find.text('Confirmar anulación'));
        await tester.tap(find.text('Confirmar anulación'));
        await tester.pumpAndSettle();
        final applied = (await h.db.select(h.db.saleAdjustments).get()).single;
        expect(applied.id, intent.operationId);
        expect(applied.eventId, intent.eventId);
        expect(find.byType(SaleAdjustmentFormScreen), findsNothing);
        expect(
          (await h.db.select(h.db.events).get()).every(
            (e) => e.deliveryStatus == 'not_required',
          ),
          true,
        );
        expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
      });
    },
  );
  test(
    'all valid fixture intentions prepare and historical reports net once',
    () async {
      for (final f in adjustmentFixtures().where((f) => f['valid'] == true)) {
        final h = await SaleAdjustmentHarness.create();
        try {
          await h.seed(f);
          await h.replayHistory(f);
          final j = object(f['payload']);
          final sale = (await SaleAdjustmentRepositoryImpl(
            h.db,
          ).watchSales().first).single;
          final original = sale.original;
          final p = await PrepareSaleAdjustment(h.service(), h.cashStore)(
            saleId: original.id,
            expectedRevision: sale.revision,
            voidSale: j['kind'] == 'void',
            reason: 'Motivo',
            action: object(j['settlement'])['action'] as String,
            reference: 'REF',
            selections: {
              for (final raw in j['lines'] as List)
                object(raw)['sale_item_id'] as String: (
                  quantity: object(raw)['quantity_atomic'] as int,
                  destination: object(raw)['destination'] as String,
                ),
            },
          );
          expect(p.totalMinor, j['total_minor']);
          await h.execute(p.toJson());
          final adjusted = (await SaleAdjustmentRepositoryImpl(
            h.db,
          ).watchSales().first).single;
          final read = adjusted.original.withAdjustments(adjusted);
          final period = ReportPeriod.day(DateTime.parse(p.businessDate));
          final gross = period.contains(original.createdAt)
              ? original.totalMinor
              : 0;
          final adjustments = adjusted.adjustments
              .where((a) => a.businessDate == p.businessDate)
              .fold(0, (n, a) => n + a.amountMinor);
          expect(
            SalesReportsCalculator.ventasTotales(period, [read]),
            BigInt.from(gross - adjustments),
          );
          expect(
            SalesReportsCalculator.ventasPorMetodo(period, [read]).totalMinor,
            BigInt.from(gross - adjustments),
          );
          if (original.paymentMethod == 'transfer') {
            final transfers = await TransferSummaryRepositoryImpl(
              h.db,
            ).watchTransferSummary(fromMs: 0, toMs: 9007199254740991).first;
            expect(
              transfers.netMinor,
              BigInt.from(
                original.totalMinor -
                    adjusted.adjustments.fold(0, (n, a) => n + a.amountMinor),
              ),
            );
          }
          final baselineProfit = SalesReportsCalculator.grossProfit(period, [
            original,
          ]).profitMinor;
          final knownDelta = read.adjustments
              .where((a) => a.businessDate == p.businessDate)
              .expand((a) => a.lines)
              .where((l) => l.recoveredCostMinor != null)
              .fold(
                BigInt.zero,
                (n, l) =>
                    n +
                    BigInt.from(l.amountMinor) -
                    BigInt.from(l.recoveredCostMinor!),
              );
          expect(
            SalesReportsCalculator.grossProfit(period, [read]).profitMinor,
            baselineProfit - knownDelta,
          );
          if (!period.contains(original.createdAt)) {
            expect(
              SalesReportsCalculator.ventasPorMetodo(period, [read]).salesCount,
              0,
            );
          }
        } finally {
          await h.close();
        }
      }
    },
  );
}
