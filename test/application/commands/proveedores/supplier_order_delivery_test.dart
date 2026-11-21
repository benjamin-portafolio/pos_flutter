import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/proveedores/confirm_supplier_receipt_command.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_receipt_input_line.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_draft_saved_payload.dart';
import 'package:pos_flutter/application/tickets/supplier_document_ticket.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/presentation/tickets/ticket_image_generator.dart';

import '../../../support/product_supplier_harness.dart';
import '../../../support/supplier_order_harness.dart';
import 'supplier_order_local_test.dart' show seedOrders;

class _SelectCounter extends QueryInterceptor {
  int count = 0;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    count++;
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'S6: catálogo 1000, pedido/recepción 50, consultas y ticket largo reales',
    () async {
      final dir = await Directory.systemTemp.createTemp('supplier-delivery-');
      final counter = _SelectCounter();
      final h = ProductSupplierHarness(
        database: AppDatabase.forTesting(
          NativeDatabase(File('${dir.path}/db.sqlite')).interceptWith(counter),
        ),
      );
      final measurements = <String, Object?>{};
      Future<T> measure<T>(String name, Future<T> Function() action) async {
        final clock = Stopwatch()..start();
        final result = await action();
        measurements['${name}_ms'] = clock.elapsedMicroseconds / 1000;
        return result;
      }

      try {
        final supplier = await seedOrders(h);
        final original = (await h.db.select(h.db.productVariants).get()).single;
        final doc = await h.newOrder(supplierId: supplier);
        await h.db.transaction(() async {
          for (var i = 1; i < 1000; i++) {
            final variant = const Uuid().v4(), resource = const Uuid().v4();
            await h.db.customStatement(
              "INSERT INTO inventory_items(id,default_unit_id,name) VALUES(?,?,'Recurso')",
              [resource, doc.items.single.unitId],
            );
            await h.db.customStatement(
              'INSERT INTO inventory_balances(inventory_item_id,quantity_on_hand_atomic,quantity_available_atomic,last_event_id) VALUES(?,3,3,?)',
              [resource, const Uuid().v4()],
            );
            await h.db.customStatement(
              'INSERT INTO product_variants(id,product_id,name,name_key,sale_price_minor,sort_order,inventory_item_id,target_stock_atomic) VALUES(?,?,?,?,1000,?,?,7)',
              [
                variant,
                original.productId,
                'Variante $i',
                'variante $i',
                i,
                resource,
              ],
            );
            await h.db.customStatement(
              'INSERT INTO variant_suppliers VALUES(?,?,3501,100)',
              [variant, supplier],
            );
            await h.db.customStatement(
              'UPDATE product_variants SET current_supplier_id=? WHERE id=?',
              [supplier, variant],
            );
          }
        });
        counter.count = 0;
        final candidates = await measure(
          'suggestions',
          h.tracking.orders.candidates,
        );
        expect(candidates.where((c) => c.isCurrent).length, 1000);
        expect(
          counter.count,
          2,
          reason: 'Grouped queries, independent of catalog size',
        );
        measurements['suggestion_selects'] = counter.count;
        final longName = List.filled(14, 'Café largo').join(' ');
        final full = SupplierOrderDraftSavedPayload.fromJson({
          ...doc.toJson(),
          'items': [
            for (final c in candidates.where((c) => c.isCurrent).take(50))
              {
                ...doc.items.single.toJson(),
                'id': const Uuid().v4(),
                'variant_id': c.variantId,
                'inventory_item_id': c.inventoryItemId,
                'product_name_snapshot': longName,
                'variant_name_snapshot': longName,
              },
          ],
          'total_minor': 14004 * 50,
        });
        measurements['payload_bytes'] = utf8
            .encode(jsonEncode(full.toJson()))
            .length;
        expect(measurements['payload_bytes'] as int, lessThanOrEqualTo(81920));
        await measure(
          'prepare',
          () async => h.orders.save(await h.orderCommand(full)),
        );
        await measure(
          'confirm',
          () async => h.orders.save(
            await h.orderCommand(await h.based(full.orderId), confirm: true),
          ),
        );
        final repo = DriftSupplierOrderRepository(h.db);
        counter.count = 0;
        expect(
          (await measure('listing', () => repo.watchOrders().first)).length,
          1,
        );
        expect(counter.count, 1);
        measurements['listing_selects'] = counter.count;
        final order = (await h.tracking.orders.find(full.orderId))!;
        final receipt = ConfirmSupplierReceiptCommand.capture(
          eventId: const Uuid().v4(),
          orderId: order.id,
          baseEventId: order.lastEventId!,
          receiptId: const Uuid().v4(),
          occurredAtMs: 500,
          items: [
            for (final l in order.document.items)
              SupplierReceiptInputLine(
                orderItemId: l.id,
                movementId: const Uuid().v4(),
                quantityAtomic: 4,
                actualPriceMinor: 100,
                referenceQuantityAtomic: 1,
              ),
          ],
        );
        await measure('receive', () => h.orders.receive(receipt));
        final detail = (await measure(
          'detail',
          () => repo.readDetail(order.id),
        ))!;
        expect(detail.receipts.single.items.length, 50);
        expect((await h.db.select(h.db.supplierReceiptItems).get()).length, 50);
        final before = (await h.db.select(h.db.inventoryBalances).get())
            .map((r) => r.toJson())
            .toList();
        // Use a real local font for macOS measurements; other hosts keep their
        // test font and must report their own rendering environment.
        if (Platform.isMacOS) {
          final font = FontLoader('Roboto')
            ..addFont(
              File(
                '/System/Library/Fonts/Supplemental/Arial.ttf',
              ).readAsBytes().then((b) => ByteData.sublistView(b)),
            );
          await font.load();
        }
        for (final isReceipt in [false, true]) {
          final ticket = SupplierDocumentTicket.build(
            detail,
            receipt: isReceipt ? detail.receipts.single : null,
          );
          final name = isReceipt ? 'receipt_ticket' : 'order_ticket';
          final bytes = await measure(
            name,
            () => TicketImageGenerator().generate(ticket),
          );
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          measurements[name] = {
            'bytes': bytes.length,
            'width': frame.image.width,
            'height': frame.image.height,
            'rgba_bytes': frame.image.width * frame.image.height * 4,
          };
          frame.image.dispose();
          codec.dispose();
          final output = Platform.environment['POS_S6_EVIDENCE'];
          if (output != null) {
            await File('$output/$name.png').writeAsBytes(bytes);
          }
        }
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .map((r) => r.toJson())
              .toList(),
          before,
        );
        measurements['rss_bytes'] = ProcessInfo.currentRss;
        measurements['max_rss_bytes'] = ProcessInfo.maxRss;
        measurements['catalog_variants'] = 1000;
        measurements['document_lines'] = 50;
        final output = Platform.environment['POS_S6_EVIDENCE'];
        if (output != null) {
          await File('$output/performance.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert(measurements),
          );
        }
        // ignore: avoid_print
        print(jsonEncode(measurements));
      } finally {
        await h.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
