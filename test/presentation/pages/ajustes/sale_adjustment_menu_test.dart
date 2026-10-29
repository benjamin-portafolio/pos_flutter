import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pos_flutter/presentation/pages/ajustes/sale_adjustment_receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/sale_adjustment_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/projections/cash_projection_store.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_adjustment_repository_impl.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/domain/repositories/sale_adjustment_repository.dart';
import 'package:pos_flutter/presentation/pages/ajustes/sale_adjustment_form_screen.dart';
import 'package:pos_flutter/presentation/pages/hoy/today_sales_screen.dart';
import '../../../support/sale_adjustment_harness.dart';

void main() {
  for (final server in [false, true]) {
    testWidgets(
      'A18 menú Hoy/detalle, cancelación y bloqueo sin compatibilidad server=$server',
      (tester) async {
        await tester.runAsync(() async {
          final font = Platform.environment['POS_SESSION4_FONT'];
          final icons = Platform.environment['POS_SESSION4_ICONS'];
          for (final entry in {
            'TabletQA': font,
            'Roboto': font,
            'MaterialIcons': icons,
          }.entries) {
            if (entry.value != null) {
              await (FontLoader(entry.key)..addFont(
                    Future.value(
                      ByteData.sublistView(
                        await File(entry.value!).readAsBytes(),
                      ),
                    ),
                  ))
                  .load();
            }
          }
          final boundary = GlobalKey();
          Future<void> capture(String name) async {
            final directory = Platform.environment['POS_SESSION4_VISUAL_DIR'];
            if (directory == null || server) return;
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '$directory/$name-1280x900.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          }

          final h = await SaleAdjustmentHarness.create();
          addTearDown(h.close);
          final f = adjustmentFixtures().firstWhere(
            (f) => f['name'] == 'cash_disabled_no_drawer',
          );
          await h.seed(f);
          final adjustments = SaleAdjustmentRepositoryImpl(h.db);
          final repository = ConfirmedSaleRepositoryImpl(
            DriftConfirmedSaleStore(h.db),
            adjustments: adjustments,
          );
          final sale = (await repository.watchSales().first).single;
          getIt.registerSingleton<SaleAdjustmentRepository>(adjustments);
          getIt.registerSingleton<SaleAdjustmentCommandService>(h.service());
          getIt.registerSingleton<CashProjectionStore>(h.cashStore);
          addTearDown(() async {
            await getIt.unregister<SaleAdjustmentRepository>();
            await getIt.unregister<SaleAdjustmentCommandService>();
            await getIt.unregister<CashProjectionStore>();
          });
          if (server) {
            h.config.update(h.config.config.copyWith(mode: AppMode.serverSync));
          }
          tester.view.physicalSize = const Size(1280, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: ThemeData(fontFamily: 'TabletQA'),
                home: Scaffold(
                  body: TodaySalesScreen(
                    repository: repository,
                    now: () => sale.createdAt.toLocal(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await capture('today');
          for (final action in ['Anular por error', 'Registrar devolución']) {
            await tester.tap(find.byTooltip('Acciones de venta'));
            await tester.pumpAndSettle();
            expect(find.text('Anular por error'), findsOneWidget);
            expect(find.text('Registrar devolución'), findsOneWidget);
            await tester.tap(find.text(action));
            await tester.pumpAndSettle();
            if (server) {
              expect(find.byType(SaleAdjustmentFormScreen), findsNothing);
              expect(
                find.textContaining('No se configuró la verificación'),
                findsOneWidget,
              );
            } else {
              expect(find.byType(SaleAdjustmentFormScreen), findsOneWidget);
              await tester.ensureVisible(find.text('Cancelar'));
              await tester.tap(find.text('Cancelar'));
              await tester.pumpAndSettle();
            }
          }
          expect(await h.db.select(h.db.saleAdjustmentIntents).get(), isEmpty);
          expect(await h.db.select(h.db.saleAdjustments).get(), isEmpty);
          expect(
            (await h.db.select(h.db.events).get()).every(
              (e) => e.deliveryStatus == 'not_required',
            ),
            true,
          );
          expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
          if (!server) {
            await tester.tap(find.byTooltip('Acciones de venta'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Anular por error'));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Motivo obligatorio'),
              'Cierre de prueba',
            );
            await tester.tap(find.text('Revisar consecuencias'));
            await tester.pumpAndSettle();
            await tester.tap(
              find.text(
                'Confirmo las consecuencias y la liquidación declarada.',
              ),
            );
            await tester.pump();
            await tester.tap(find.text('Confirmar anulación'));
            await tester.pumpAndSettle();
            expect(find.byType(SaleAdjustmentReceiptScreen), findsOneWidget);
            expect(find.text('ANULACIÓN POR ERROR'), findsOneWidget);
            expect(
              (await h.db.select(h.db.saleAdjustments).get())
                  .single
                  .amountMinor,
              sale.totalMinor,
            );
            expect(
              (await repository.watchSales().first).single.totalMinor,
              sale.totalMinor,
            );
            await tester.pageBack();
            await tester.pumpAndSettle();
            expect(find.textContaining('Anulada'), findsOneWidget);
          }
          await tester.tap(find.byKey(ValueKey('today-sale-${sale.id}')));
          for (var n = 0; n < 100; n++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 20));
            if (find.byType(Image).evaluate().isNotEmpty) break;
          }
          await tester.pumpAndSettle();
          expect(find.byTooltip('Acciones de venta'), findsOneWidget);
          await capture('sale-detail');
          await tester.tap(find.byTooltip('Acciones de venta'));
          await tester.pumpAndSettle();
          expect(find.text('Anular por error'), findsOneWidget);
          expect(find.text('Registrar devolución'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        });
      },
    );
  }
}
