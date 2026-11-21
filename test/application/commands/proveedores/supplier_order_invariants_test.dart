import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/proveedores/cancel_supplier_order_command.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_draft_saved_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/supplier_order_harness.dart';
import 'supplier_order_local_test.dart' show seedOrders;

void main() {
  test(
    'Elegibilidad: producto/variante/proveedor/recurso inactivos, receta y sin seguimiento',
    () async {
      final h = ProductSupplierHarness();
      try {
        final supplier = await seedOrders(h);
        final c = (await h.tracking.orders.candidates()).firstWhere(
          (c) => c.isCurrent,
        );
        Future<void> absent() async => expect(
          (await h.tracking.orders.candidates()).where(
            (r) => r.supplierId == supplier,
          ),
          isEmpty,
        );
        await (h.db.update(h.db.products)
              ..where((t) => t.id.equals(c.productId)))
            .write(const ProductsCompanion(active: Value(false)));
        await absent();
        await (h.db.update(h.db.products)
              ..where((t) => t.id.equals(c.productId)))
            .write(const ProductsCompanion(active: Value(true)));
        await (h.db.update(h.db.productVariants)
              ..where((t) => t.id.equals(c.variantId)))
            .write(const ProductVariantsCompanion(active: Value(false)));
        await absent();
        await (h.db.update(h.db.productVariants)
              ..where((t) => t.id.equals(c.variantId)))
            .write(const ProductVariantsCompanion(active: Value(true)));
        await (h.db.update(h.db.suppliers)..where((t) => t.id.equals(supplier)))
            .write(const SuppliersCompanion(active: Value(false)));
        await absent();
        await (h.db.update(h.db.suppliers)..where((t) => t.id.equals(supplier)))
            .write(const SuppliersCompanion(active: Value(true)));
        await (h.db.update(h.db.inventoryItems)
              ..where((t) => t.id.equals(c.inventoryItemId)))
            .write(const InventoryItemsCompanion(active: Value(false)));
        await absent();
        await (h.db.update(h.db.inventoryItems)
              ..where((t) => t.id.equals(c.inventoryItemId)))
            .write(const InventoryItemsCompanion(active: Value(true)));
        await h.db
            .into(h.db.recipeComponents)
            .insert(
              RecipeComponentsCompanion.insert(
                variantId: c.variantId,
                inventoryItemId: c.inventoryItemId,
                quantityAtomic: 1,
              ),
            );
        await absent();
        await h.db.delete(h.db.recipeComponents).go();
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(c.variantId))).write(
          const ProductVariantsCompanion(inventoryItemId: Value(null)),
        );
        await absent();
      } finally {
        await h.dispose();
      }
    },
  );
  test(
    'Cero, null, faltantes cerrados y restricciones de cancelación con recepciones existentes',
    () async {
      final h = ProductSupplierHarness();
      try {
        final supplier = await seedOrders(h);
        final c = (await h.tracking.orders.candidates()).firstWhere(
          (c) => c.isCurrent,
        );
        final doc = await h.newOrder(supplierId: supplier);
        await h.orders.save(await h.orderCommand(doc));
        await h.orders.save(
          await h.orderCommand(await h.based(doc.orderId), confirm: true),
        );
        await (h.db.update(
          h.db.supplierOrderItems,
        )..where((t) => t.orderId.equals(doc.orderId))).write(
          const SupplierOrderItemsCompanion(closedQuantityAtomic: Value(4)),
        );
        expect((await h.tracking.orders.candidates()).first.suggestedAtomic, 4);
        await (h.db.update(h.db.supplierOrders)
              ..where((t) => t.id.equals(doc.orderId)))
            .write(const SupplierOrdersCompanion(status: Value('closed')));
        expect((await h.tracking.orders.candidates()).first.suggestedAtomic, 4);
        await (h.db.update(h.db.productVariants)
              ..where((t) => t.id.equals(c.variantId)))
            .write(const ProductVariantsCompanion(targetStockAtomic: Value(0)));
        expect((await h.tracking.orders.candidates()).first.suggestedAtomic, 0);
        expect(
          await DriftSupplierOrderRepository(h.db).watchIssues().first,
          isEmpty,
        );
        final second = await h.newOrder(supplierId: supplier, quantity: 1);
        await h.orders.save(await h.orderCommand(second));
        await h.orders.save(
          await h.orderCommand(await h.based(second.orderId), confirm: true),
        );
        final o = (await h.tracking.orders.find(second.orderId))!;
        // Estructura S1 para acreditar el límite de S3; no ejecuta recepción ni movimientos.
        await h.db
            .into(h.db.supplierReceipts)
            .insert(
              SupplierReceiptsCompanion.insert(
                id: const Uuid().v4(),
                orderId: o.id,
                eventId: const Uuid().v4(),
                intentHash: 'a' * 64,
                baseEventId: o.lastEventId!,
                occurredAtMs: 100,
                totalMinor: 0,
              ),
            );
        await expectLater(
          h.orders.cancel(
            CancelSupplierOrderCommand(
              eventId: const Uuid().v4(),
              orderId: o.id,
              baseEventId: o.lastEventId!,
              occurredAtMs: 101,
            ),
          ),
          throwsStateError,
        );
        expect((await h.tracking.orders.find(o.id))!.status, 'confirmed');
      } finally {
        await h.dispose();
      }
    },
  );
  test(
    'Precio desconocido/cero y fallo de proyección revierte evento/documento completos en ambos modos',
    () async {
      for (final mode in AppMode.values) {
        final h = ProductSupplierHarness(mode: mode);
        try {
          final supplier = await seedOrders(h);
          final doc = await h.newOrder(supplierId: supplier);
          final bad = SupplierOrderDraftSavedPayload.fromJson({
            ...doc.toJson(),
            'items': doc.items
                .map(
                  (l) => {
                    ...l.toJson(),
                    'inventory_item_id': const Uuid().v4(),
                  },
                )
                .toList(),
          });
          final count = (await h.db.select(h.db.events).get()).length;
          await expectLater(
            h.orders.save(await h.orderCommand(bad)),
            throwsStateError,
          );
          expect((await h.db.select(h.db.events).get()).length, count);
          expect(await h.db.select(h.db.supplierOrders).get(), isEmpty);
          final unknown = SupplierOrderDraftSavedPayload.fromJson({
            ...doc.toJson(),
            'total_minor': null,
            'items': doc.items
                .map(
                  (l) => {
                    ...l.toJson(),
                    'quoted_price_minor': null,
                    'total_minor': null,
                  },
                )
                .toList(),
          });
          await h.orders.save(await h.orderCommand(unknown));
          await h.orders.save(
            await h.orderCommand(await h.based(doc.orderId), confirm: true),
          );
          expect(
            (await h.tracking.orders.find(doc.orderId))!.document.totalMinor,
            isNull,
          );
        } finally {
          await h.dispose();
        }
      }
    },
  );
}
