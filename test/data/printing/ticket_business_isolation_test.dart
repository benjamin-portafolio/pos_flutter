import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/printing/esc_pos_ticket_encoder.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/presentation/pages/caja/models/sale_receipt_display.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/models/quotation_display.dart';

import '../../support/fake_printer_gateway.dart';
import '../../support/quotation_harness.dart';
import '../../support/thermal_ticket_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in AppMode.values) {
    test(
      'real fixture ${mode.name}: sale/quotation print and manual reprint change no table or sync',
      () async {
        var httpCalls = 0;
        await HttpOverrides.runZoned(
          () async {
            final h = QuotationHarness(mode: mode);
            final gateway = FakePrinterGateway();
            final service = TicketPrintService(
              gateway,
              encoder: const EscPosTicketEncoder(),
            );
            try {
              await h.seed();
              await h.add();
              await h.add(QuotationHarness.measuredId);
              final intent = await h.intent();
              await h.service().guardar(intent);
              final quotation = (await h.repository.findById(
                intent.quotationId,
              ))!;
              final visible = QuotationDisplay(
                quotation,
                await h.repository.estimate(quotation),
              ).ticket;
              await h.confirm();
              await h.add();
              await h.confirm(method: 'transfer');
              final customer = await h.customer();
              await h.add();
              await h.confirm(method: 'credit', clienteId: customer);
              final receipts = await ConfirmedSaleRepositoryImpl(
                DriftConfirmedSaleStore(h.db),
              ).watchSales().first;
              expect(receipts.map((s) => s.paymentMethod).toSet(), {
                'cash',
                'transfer',
                'credit',
              });
              // The current catalog changes after the confirmed snapshots and the
              // visible quotation were captured. Printing has no repository reads.
              await (h.db.update(
                h.db.productVariants,
              )..where((t) => t.id.equals(QuotationHarness.directId))).write(
                const ProductVariantsCompanion(salePriceMinor: Value(99900)),
              );
              final before = await h.contents();
              final documents = [
                visible,
                for (final sale in receipts) SaleReceiptDisplay(sale).ticket,
              ];
              for (final document in documents) {
                expect(document.itemRows.first[1], r'$35.00');
                for (var attempt = 0; attempt < 2; attempt++) {
                  expect(
                    (await service.printTicket(
                      document: document,
                      profile: thermalProfile(),
                    )).sent,
                    isTrue,
                  );
                  expect(await h.contents(), before);
                }
              }
              expect(
                gateway.calls.where((c) => c.startsWith('connect:')),
                hasLength(8),
              );
              expect(gateway.calls.where((c) => c == 'close'), hasLength(8));
              final refs = await h.db.select(h.db.eventRefs).get();
              if (mode == AppMode.standalone) {
                expect(refs, isEmpty);
                expect(
                  (await h.db.select(h.db.events).get()).every(
                    (e) => e.deliveryStatus == 'not_required',
                  ),
                  isTrue,
                );
              } else {
                expect(refs, isNotEmpty);
              }
              expect(await h.contents(), before);
            } finally {
              await service.dispose();
              await h.dispose();
            }
          },
          createHttpClient: (_) {
            httpCalls++;
            throw StateError('Printing must never initiate synchronization');
          },
        );
        expect(httpCalls, 0);
      },
    );
  }
}
