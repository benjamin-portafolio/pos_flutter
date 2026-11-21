import 'package:pos_flutter/application/sync/payloads/supplier_order_draft_saved_payload.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_receipt_input_line.dart';
import 'dart:io';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/proveedores/confirm_supplier_receipt_command.dart';
import 'package:pos_flutter/application/commands/proveedores/close_supplier_order_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_receipt_confirmed_payload.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_closed_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/supplier_order_harness.dart';
import 'supplier_order_local_test.dart' show seedOrders;

Future<String> confirmedOrder(ProductSupplierHarness h) async {
  final supplier = await seedOrders(h);
  final d = await h.newOrder(supplierId: supplier);
  await h.orders.save(await h.orderCommand(d));
  await h.orders.save(
    await h.orderCommand(await h.based(d.orderId), confirm: true),
  );
  return d.orderId;
}

Future<ConfirmSupplierReceiptCommand> receipt(
  ProductSupplierHarness h,
  String order,
  int qty, {
  bool overage = false,
  int price = 100,
}) async {
  final o = (await h.tracking.orders.find(order))!;
  final line = o.document.items.single;
  return ConfirmSupplierReceiptCommand(
    eventId: const Uuid().v4(),
    payload: SupplierReceiptConfirmedPayload.fromJson({
      'contract_version': 1,
      'order_id': order,
      'base_event_id': o.lastEventId,
      'receipt_id': const Uuid().v4(),
      'occurred_at_ms': 300,
      'total_minor': price * qty,
      'items': [
        {
          'order_item_id': line.id,
          'movement_id': const Uuid().v4(),
          'quantity_atomic': qty,
          'actual_price_minor': price,
          'reference_quantity_atomic': 1,
          'total_minor': price * qty,
          'overage_acknowledged': overage,
        },
      ],
    }),
  );
}

void main() {
  test(
    'Captura tipada: cero omite movimiento; todo cero y partidas repetidas rechazan',
    () async {
      final h = ProductSupplierHarness();
      try {
        final id = await confirmedOrder(h),
            o = (await h.tracking.orders.find(id))!;
        final zero = SupplierReceiptInputLine(
          orderItemId: const Uuid().v4(),
          movementId: const Uuid().v4(),
          quantityAtomic: 0,
          actualPriceMinor: 100,
          referenceQuantityAtomic: 1,
        );
        final one = SupplierReceiptInputLine(
          orderItemId: o.document.items.single.id,
          movementId: const Uuid().v4(),
          quantityAtomic: 1,
          actualPriceMinor: 100,
          referenceQuantityAtomic: 1,
        );
        ConfirmSupplierReceiptCommand capture(
          List<SupplierReceiptInputLine> items,
        ) => ConfirmSupplierReceiptCommand.capture(
          eventId: const Uuid().v4(),
          orderId: id,
          baseEventId: o.lastEventId!,
          receiptId: const Uuid().v4(),
          occurredAtMs: 500,
          items: items,
        );
        expect(() => capture([zero]), throwsFormatException);
        expect(() => capture([one, one]), throwsFormatException);
        final c = capture([zero, one]);
        await h.orders.receive(c);
        expect(c.payload.items.length, 1);
        expect(
          (await h.db.select(h.db.inventoryMovements).get())
              .where((m) => m.eventId == c.eventId)
              .length,
          1,
        );
      } finally {
        await h.dispose();
      }
    },
  );
  for (final mutation in [
    'UPDATE products SET active=0',
    'UPDATE product_variants SET active=0',
    'UPDATE suppliers SET active=0',
    'UPDATE inventory_items SET active=0',
    'UPDATE units SET active=0',
    'UPDATE product_variants SET inventory_item_id=NULL',
    "UPDATE units SET atomic_factor=2 WHERE dimension='count'",
    "UPDATE units SET dimension='mass' WHERE dimension='count'",
  ]) {
    test('Cambio de catálogo bloquea sin efectos: $mutation', () async {
      final h = ProductSupplierHarness();
      try {
        final id = await confirmedOrder(h), c = await receipt(h, id, 4);
        await h.db.customUpdate(mutation);
        await expectLater(h.orders.receive(c), throwsStateError);
        expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .single
              .quantityOnHandAtomic,
          3,
        );
        expect((await h.tracking.orders.find(id))!.status, 'confirmed');
      } finally {
        await h.dispose();
      }
    });
  }

  test(
    '50 partidas SQLite: rollback de segunda partida y doble ejecución simultánea',
    () async {
      final h = ProductSupplierHarness();
      try {
        final supplier = await seedOrders(h);
        final original = (await h.db.select(h.db.productVariants).get()).single;
        final doc = await h.newOrder(supplierId: supplier);
        final lines = [doc.items.single.toJson()];
        for (var i = 1; i < 50; i++) {
          final id = const Uuid().v4(), resource = const Uuid().v4();
          await h.db.customStatement(
            "INSERT INTO inventory_items(id,default_unit_id,name,created_event_id,last_event_id) VALUES(?,?,'Recurso',?,?)",
            [
              resource,
              doc.items.single.unitId,
              const Uuid().v4(),
              const Uuid().v4(),
            ],
          );
          await h.db.customStatement(
            "INSERT INTO inventory_balances(inventory_item_id,quantity_on_hand_atomic,quantity_available_atomic,last_event_id) VALUES(?,0,0,?)",
            [resource, const Uuid().v4()],
          );
          await h.db.customStatement(
            "INSERT INTO product_variants(id,product_id,name,name_key,sale_price_minor,sort_order,inventory_item_id) VALUES(?,?,?, ?,1000,?,?)",
            [id, original.productId, 'Otra $i', 'otra $i', i, resource],
          );
          await h.db.customStatement(
            'INSERT INTO variant_suppliers VALUES(?,?,3501,100)',
            [id, supplier],
          );
          lines.add({
            ...doc.items.single.toJson(),
            'id': const Uuid().v4(),
            'variant_id': id,
            'inventory_item_id': resource,
            'variant_name_snapshot': 'Otra $i',
          });
        }
        final full = SupplierOrderDraftSavedPayload.fromJson({
          ...doc.toJson(),
          'items': lines,
          'total_minor': 14004 * 50,
        });
        await h.orders.save(await h.orderCommand(full));
        await h.orders.save(
          await h.orderCommand(await h.based(full.orderId), confirm: true),
        );
        final o = (await h.tracking.orders.find(full.orderId))!;
        final c = ConfirmSupplierReceiptCommand.capture(
          eventId: const Uuid().v4(),
          orderId: o.id,
          baseEventId: o.lastEventId!,
          receiptId: const Uuid().v4(),
          occurredAtMs: 300,
          items: [
            for (final l in o.document.items)
              SupplierReceiptInputLine(
                orderItemId: l.id,
                movementId: const Uuid().v4(),
                quantityAtomic: 1,
                actualPriceMinor: 100,
                referenceQuantityAtomic: 1,
              ),
          ],
        );
        final before = (await h.db.select(h.db.inventoryBalances).get())
            .singleWhere((b) => b.inventoryItemId == original.inventoryItemId);
        await h.db.customStatement(
          "CREATE TEMP TRIGGER fail_second BEFORE INSERT ON supplier_receipt_items WHEN NEW.order_item_id='${o.document.items[1].id}' BEGIN SELECT RAISE(ABORT,'second line'); END",
        );
        await expectLater(h.orders.receive(c), throwsA(anything));
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .singleWhere((b) => b.inventoryItemId == original.inventoryItemId)
              .toJson(),
          before.toJson(),
        );
        expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
        expect(
          (await h.db.select(h.db.inventoryMovements).get()).where(
            (m) => m.eventId == c.eventId,
          ),
          isEmpty,
        );
        await h.db.customStatement('DROP TRIGGER fail_second');
        await Future.wait([h.orders.receive(c), h.orders.receive(c)]);
        final after = (await h.db.select(h.db.inventoryBalances).get())
            .singleWhere((b) => b.inventoryItemId == original.inventoryItemId);
        expect(
          (await h.db.select(h.db.inventoryBalances).get()).fold<int>(
            0,
            (n, b) => n + b.quantityOnHandAtomic,
          ),
          53,
        );
        expect(after.version, before.version + 1);
        expect((await h.db.select(h.db.supplierReceiptItems).get()).length, 50);
        await h.tracking.orders.restore(
          (await h.tracking.history.eventById(c.eventId))!,
        );
        expect(
          (await h.db.select(h.db.inventoryBalances).get()).fold<int>(
            0,
            (n, b) => n + b.quantityOnHandAtomic,
          ),
          3,
        );
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .singleWhere((b) => b.inventoryItemId == original.inventoryItemId)
              .version,
          before.version,
        );
      } finally {
        await h.dispose();
      }
    },
  );
  test(
    'Medidos: átomos y referencia conservados en parciales y precio real',
    () async {
      final h = ProductSupplierHarness();
      try {
        final supplier = await seedOrders(h, measured: true);
        final d = await h.newOrder(supplierId: supplier);
        await h.orders.save(await h.orderCommand(d));
        await h.orders.save(
          await h.orderCommand(await h.based(d.orderId), confirm: true),
        );
        await h.orders.receive(await receipt(h, d.orderId, 1500, price: 2));
        expect(
          (await h.tracking.orders.candidates()).first.pendingAtomic,
          2500,
        );
        await h.orders.receive(await receipt(h, d.orderId, 2500, price: 3));
        expect((await h.tracking.orders.find(d.orderId))!.status, 'received');
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .single
              .quantityOnHandAtomic,
          7000,
        );
        expect(
          (await h.db.select(h.db.supplierReceipts).get())
              .map((r) => r.totalMinor)
              .toList(),
          [3000, 7500],
        );
      } finally {
        await h.dispose();
      }
    },
  );
  for (final mode in AppMode.values) {
    test(
      '${mode.name}: 3-2+4=5, reintento, reapertura y undo tardío conservan sucesores',
      () async {
        final dir = await Directory.systemTemp.createTemp('supplier-receipt-');
        final file = File('${dir.path}/db.sqlite');
        var h = ProductSupplierHarness(
          database: AppDatabase.forTesting(NativeDatabase(file)),
          mode: mode,
        );
        try {
          final id = await confirmedOrder(h);
          // Intervening stock consumption; business sale/HTTP case is separate.
          await h.db.customUpdate(
            'UPDATE inventory_balances SET quantity_on_hand_atomic=1,quantity_available_atomic=1',
          );
          final c = await receipt(h, id, 4, price: 120);
          await h.orders.receive(c);
          await h.orders.receive(c);
          expect(
            (await h.db.select(h.db.inventoryBalances).get())
                .single
                .quantityOnHandAtomic,
            5,
          );
          expect((await h.tracking.orders.find(id))!.status, 'received');
          final e = (await h.tracking.history.eventById(c.eventId))!;
          expect(
            e.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          expect(
            (await h.db.select(h.db.eventRefs).get()).isEmpty,
            mode == AppMode.standalone,
          );
          final snapshot =
              (await h.db.select(h.db.supplierReceipts).get()).single;
          expect(snapshot.intentHash.length, 64);
          await h.dispose();
          h = ProductSupplierHarness(
            database: AppDatabase.forTesting(NativeDatabase(file)),
            mode: mode,
          );
          await h.orders.receive(c);
          expect((await h.db.select(h.db.supplierReceipts).get()).length, 1);
          await expectLater(
            h.orders.receive(
              ConfirmSupplierReceiptCommand(
                eventId: c.eventId,
                payload: SupplierReceiptConfirmedPayload.fromJson({
                  ...c.payload.toJson(),
                  'occurred_at_ms': 301,
                }),
              ),
            ),
            throwsStateError,
          );
          // An independent successor changes the live balance after receipt.
          await h.db.customUpdate(
            'UPDATE inventory_balances SET quantity_on_hand_atomic=3,quantity_available_atomic=3,last_event_id=?',
            variables: [Variable(const Uuid().v4())],
          );
          await h.tracking.orders.restore(e);
          expect(
            (await h.db.select(h.db.inventoryBalances).get())
                .single
                .quantityOnHandAtomic,
            -1,
          );
          expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
          expect((await h.tracking.orders.find(id))!.status, 'confirmed');
        } finally {
          await h.dispose();
          await dir.delete(recursive: true);
        }
      },
    );
    test(
      '${mode.name}: parcial 3/4, luego 1; cierre exacto libera pendiente sin stock',
      () async {
        final h = ProductSupplierHarness(mode: mode);
        try {
          final id = await confirmedOrder(h);
          await h.orders.receive(await receipt(h, id, 3));
          expect((await h.tracking.orders.find(id))!.status, 'partial');
          expect((await h.tracking.orders.candidates()).first.pendingAtomic, 1);
          await h.orders.receive(await receipt(h, id, 1));
          expect((await h.tracking.orders.find(id))!.status, 'received');
          // A second document can explicitly close its partial remainder.
          final supplier = (await h.tracking.orders.find(
            id,
          ))!.document.supplierId;
          final d = await h.newOrder(supplierId: supplier, quantity: 4);
          await h.orders.save(await h.orderCommand(d));
          await h.orders.save(
            await h.orderCommand(await h.based(d.orderId), confirm: true),
          );
          await h.orders.receive(await receipt(h, d.orderId, 3));
          final o = (await h.tracking.orders.find(d.orderId))!;
          final before = (await h.db.select(h.db.inventoryBalances).get())
              .single
              .toJson();
          final close = CloseSupplierOrderCommand(
            eventId: const Uuid().v4(),
            payload: SupplierOrderClosedPayload.fromJson({
              'contract_version': 1,
              'order_id': o.id,
              'base_event_id': o.lastEventId,
              'occurred_at_ms': 400,
              'items': [
                {
                  'order_item_id': o.document.items.single.id,
                  'closed_quantity_atomic': 1,
                },
              ],
            }),
          );
          await h.orders.closeRemainder(close);
          await h.orders.closeRemainder(close);
          expect((await h.tracking.orders.find(o.id))!.status, 'closed');
          expect((await h.tracking.orders.candidates()).first.pendingAtomic, 0);
          expect(
            (await h.db.select(h.db.inventoryBalances).get()).single.toJson(),
            before,
          );
          await expectLater(
            h.orders.receive(await receipt(h, o.id, 1)),
            throwsStateError,
          );
          await h.tracking.orders.restore(
            (await h.tracking.history.eventById(close.eventId))!,
          );
          expect((await h.tracking.orders.find(o.id))!.status, 'partial');
          expect((await h.tracking.orders.candidates()).first.pendingAtomic, 1);
        } finally {
          await h.dispose();
        }
      },
    );
  }
  test(
    'Exceso explícito, precio real solo documental; fallo intermedio revierte todo',
    () async {
      final h = ProductSupplierHarness();
      try {
        final id = await confirmedOrder(h);
        final before = (await h.db.select(h.db.productVariants).get()).single
            .toJson();
        await expectLater(
          h.orders.receive(await receipt(h, id, 5)),
          throwsStateError,
        );
        final c = await receipt(h, id, 5, overage: true, price: 0);
        await h.db.customStatement(
          "CREATE TEMP TRIGGER fail_receipt BEFORE INSERT ON supplier_receipt_items BEGIN SELECT RAISE(ABORT,'forced'); END",
        );
        await expectLater(h.orders.receive(c), throwsA(anything));
        expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .single
              .quantityOnHandAtomic,
          3,
        );
        expect(await h.tracking.history.eventById(c.eventId), isNull);
        await h.db.customStatement('DROP TRIGGER fail_receipt');
        await h.orders.receive(c);
        expect(
          (await h.db.select(h.db.productVariants).get()).single.toJson(),
          before,
        );
        expect(
          (await h.db.select(h.db.supplierReceipts).get()).single.totalMinor,
          0,
        );
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .single
              .quantityOnHandAtomic,
          8,
        );
      } finally {
        await h.dispose();
      }
    },
  );
}
