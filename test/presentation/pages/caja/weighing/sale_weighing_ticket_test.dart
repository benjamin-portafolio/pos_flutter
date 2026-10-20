import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/presentation/pages/caja/models/sale_receipt_display.dart';
import 'package:pos_flutter/presentation/pages/caja/weighing/sale_weighing_controller.dart';

import '../../../../support/fake_scale_gateway.dart';
import '../../../../support/quotation_harness.dart';
import 'sale_weighing_controller_test.dart' show profile, weight;

void main() {
  for (final mode in AppMode.values) {
    test(
      'B38 peso revisado, acumulación y ticket reabierto ${mode.name}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'weighing-ticket-',
        );
        final path = '${directory.path}/test.sqlite';
        final harness = QuotationHarness(
          database: AppDatabase.forTesting(NativeDatabase(File(path))),
          mode: mode,
        );
        final gateway = FakeScaleGateway();
        final service = ScaleSessionService(gateway);
        try {
          await harness.seed();
          await harness.db.productoDao.actualizarVariante(
            QuotationHarness.measuredId,
            const ProductVariantsCompanion(salePriceMinor: Value(5000)),
          );
          final products = ProductoRepositoryImpl(
            productoDao: harness.db.productoDao,
          );
          final drafts = SaleDraftRepositoryImpl(
            saleDao: harness.db.saleDao,
            userId: harness.context.userId,
            deviceId: harness.context.deviceId,
          );
          final conditions = (await products.obtenerCondicionesVentaMedida(
            QuotationHarness.measuredId,
          ))!;
          var totalGrams = 0;
          for (final grams in [400, 430]) {
            final controller = SaleWeighingController(
              conditions: conditions,
              profile: profile,
              service: service,
              draft: drafts.watchCurrentDraft(),
            );
            try {
              final deadline = DateTime.now().add(const Duration(seconds: 5));
              controller.start();
              while (gateway.reads.length < (grams == 400 ? 1 : 2)) {
                if (DateTime.now().isAfter(deadline)) {
                  fail('Consulta no iniciada');
                }
                await Future<void>.delayed(Duration.zero);
              }
              gateway.reads.last.complete([weight(grams)]);
              while (!controller.canAccept) {
                if (DateTime.now().isAfter(deadline)) {
                  fail('Peso no disponible');
                }
                await Future<void>.delayed(Duration.zero);
              }
              expect(controller.capture!.measuredQuantityAtomic, grams);
              expect(controller.capture!.totalMinor, grams * 5);
              totalGrams += grams;
              expect(
                (controller.accumulated ?? controller.capture)!.totalMinor,
                totalGrams * 5,
              );
              controller.presented(controller.revision);
              final result = controller.accept(controller.revision)!;
              await controller.stop();
              await harness.drafts.agregar(
                result.toCommand(QuotationHarness.measuredId),
              );
              final persisted = (await drafts.watchCurrentDraft().first)!;
              expect(persisted.items.single.measuredQuantityAtomic, totalGrams);
              expect(persisted.totalMinor, totalGrams * 5);
            } finally {
              controller.dispose();
              await controller.stop();
            }
          }
          // Confirmation only in this isolated test DB; no real purchase/printing.
          await harness.confirm();
          await harness.db.close();
          final reopened = AppDatabase.forTesting(NativeDatabase(File(path)));
          try {
            final sale = (await ConfirmedSaleRepositoryImpl(
              DriftConfirmedSaleStore(reopened),
            ).watchSales().first).single;
            expect(sale.items.single.measuredQuantityAtomic, 830);
            expect(sale.totalMinor, 4150);
            final ticket = SaleReceiptDisplay(sale).ticket;
            expect(ticket.itemRows.single[2], '0.830 kg');
            expect(ticket.itemRows.single[3], r'$41.50');
            expect(ticket.totals, contains(('Total general', r'$41.50')));
          } finally {
            await reopened.close();
          }
        } finally {
          await service.dispose();
          await harness.dispose();
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
