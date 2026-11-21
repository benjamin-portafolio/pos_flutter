import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/proveedores/cancel_supplier_order_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/supplier_order_harness.dart';

Future<String> seedOrders(
  ProductSupplierHarness h, {
  bool measured = false,
}) async {
  final supplier = await h.supplier('Principal');
  final alt = await h.supplier('Alternativo');
  await h.commands.crearArticulo(
    CrearArticuloCommand.conVariantes(
      nombre: 'Café',
      saleConfiguration: measured
          ? MeasuredSaleConfiguration(
              saleUnitId: InventoryUnitIds.gram,
              priceReferenceQuantityAtomic: 1,
            )
          : const UnitSaleConfiguration(),
      variantes: [
        CrearArticuloVarianteCommand.conProveedores(
          nombre: null,
          precioVenta: '10',
          costoEstandar: null,
          inventoryUnitId: measured
              ? InventoryUnitIds.kilogram
              : InventoryUnitIds.piece,
          initialStockQuantity: '3',
          proveedores: [
            for (final id in [supplier, alt])
              ProveedorVariante(
                proveedorId: id,
                precioInformadoMenor: 3501,
                fechaInformadaMs: 100,
              ),
          ],
          currentSupplier: CambioExplicito.establecer(supplier),
          targetStock: const CambioExplicito.establecer('7'),
        ),
      ],
    ),
  );
  return supplier;
}

void main() {
  for (final mode in AppMode.values) {
    for (final measured in [false, true]) {
      test(
        '${mode.name} medido=$measured: SQLite en disco, borrador/reapertura/confirmar/reintentar/cancelar sin stock',
        () async {
          final dir = await Directory.systemTemp.createTemp('orders-s3-');
          final file = File('${dir.path}/db.sqlite');
          var h = ProductSupplierHarness(
            database: AppDatabase.forTesting(NativeDatabase(file)),
            mode: mode,
          );
          try {
            await seedOrders(h, measured: measured);
            final c = (await h.tracking.orders.candidates()).firstWhere(
              (c) => c.isCurrent,
            );
            expect(c.suggestedAtomic, measured ? 4000 : 4);
            final balances = (await h.db.select(h.db.inventoryBalances).get())
                .map((r) => r.toJson())
                .toList();
            final movements = (await h.db.select(h.db.inventoryMovements).get())
                .map((r) => r.toJson())
                .toList();
            final doc = await h.newOrder(supplierId: c.supplierId);
            final draft = await h.orderCommand(doc);
            await h.orders.save(draft);
            await h.orders.save(draft);
            expect(
              (await h.tracking.orders.candidates()).first.suggestedAtomic,
              c.suggestedAtomic,
            );
            final count = (await h.db.select(h.db.events).get()).length;
            await h.dispose();
            h = ProductSupplierHarness(
              database: AppDatabase.forTesting(NativeDatabase(file)),
              mode: mode,
            );
            expect(
              (await h.tracking.orders.find(
                doc.orderId,
              ))!.document.toJson()['items'],
              doc.toJson()['items'],
            );
            final confirm = await h.orderCommand(
              await h.based(doc.orderId),
              confirm: true,
            );
            await h.orders.save(confirm);
            await h.orders.save(confirm);
            expect((await h.db.select(h.db.events).get()).length, count + 1);
            expect(
              (await h.tracking.orders.candidates()).first.suggestedAtomic,
              0,
            );
            await expectLater(
              h.orders.save(await h.orderCommand(doc)),
              throwsStateError,
            );
            final confirmed = (await h.tracking.orders.find(doc.orderId))!;
            await (h.db.update(h.db.suppliers)
                  ..where((t) => t.id.equals(c.supplierId)))
                .write(const SuppliersCompanion(name: Value('Nombre nuevo')));
            expect(
              (await h.tracking.orders.find(
                doc.orderId,
              ))!.document.supplierNameSnapshot,
              'Principal',
            );
            final cancel = CancelSupplierOrderCommand(
              eventId: const Uuid().v4(),
              orderId: doc.orderId,
              baseEventId: confirmed.lastEventId!,
              occurredAtMs: 200,
            );
            await h.orders.cancel(cancel);
            await h.orders.cancel(cancel);
            expect(
              (await h.tracking.orders.candidates()).first.suggestedAtomic,
              c.suggestedAtomic,
            );
            expect(
              (await h.db.select(h.db.inventoryBalances).get())
                  .map((r) => r.toJson())
                  .toList(),
              balances,
            );
            expect(
              (await h.db.select(h.db.inventoryMovements).get())
                  .map((r) => r.toJson())
                  .toList(),
              movements,
            );
            final event = (await h.tracking.history.eventById(
              confirm.eventId,
            ))!;
            expect(
              event.deliveryStatus,
              mode == AppMode.standalone ? 'not_required' : 'pending',
            );
            expect(
              (await h.db.select(h.db.eventRefs).get()).isEmpty,
              mode == AppMode.standalone,
            );
          } finally {
            await h.dispose();
            await dir.delete(recursive: true);
          }
        },
      );
    }
  }
  test(
    'Pendientes de todos los proveedores, solapamiento, base obsoleta y restauración inversa',
    () async {
      final h = ProductSupplierHarness();
      try {
        final supplier = await seedOrders(h);
        final doc = await h.newOrder(supplierId: supplier);
        await h.orders.save(await h.orderCommand(doc));
        final based = await h.based(doc.orderId);
        final first = await h.orderCommand(based, confirm: true);
        await h.orders.save(first);
        final variant = (await h.db.select(h.db.productVariants).get()).single;
        final alt = (await h.tracking.orders.candidates())
            .firstWhere((c) => !c.isCurrent)
            .supplierId;
        await (h.db.update(h.db.productVariants)
              ..where((t) => t.id.equals(variant.id)))
            .write(ProductVariantsCompanion(currentSupplierId: Value(alt)));
        expect(
          (await h.tracking.orders.candidates())
              .firstWhere((c) => c.isCurrent)
              .suggestedAtomic,
          0,
        );
        final second = await h.newOrder(supplierId: alt, quantity: 4);
        await h.orders.save(await h.orderCommand(second));
        await h.orders.save(
          await h.orderCommand(await h.based(second.orderId), confirm: true),
        );
        expect(
          (await DriftSupplierOrderRepository(
            h.db,
          ).watchOrders().first).every((o) => o.overlaps),
          isTrue,
        );
        final stale = await h.orderCommand(based, confirm: true);
        await expectLater(h.orders.save(stale), throwsStateError);
        final original = (await h.tracking.history.eventById(first.eventId))!;
        await h.db.transaction(() => h.tracking.orders.restore(original));
        expect((await h.tracking.orders.find(doc.orderId))!.status, 'draft');
      } finally {
        await h.dispose();
      }
    },
  );
  test(
    'Cálculo: >= objetivo, negativo, cero/null; actividad y revisión de bases',
    () async {
      final h = ProductSupplierHarness();
      try {
        final supplier = await seedOrders(h);
        final c = (await h.tracking.orders.candidates()).first;
        final doc = await h.newOrder(supplierId: supplier);
        await h.orders.save(await h.orderCommand(doc));
        final review = await h.orderCommand(
          await h.based(doc.orderId),
          confirm: true,
        );
        final balance =
            (await h.db.select(h.db.inventoryBalances).get()).single;
        for (final value in [7, 10, -2, 0]) {
          await (h.db.update(h.db.inventoryBalances)..where(
                (t) => t.inventoryItemId.equals(balance.inventoryItemId),
              ))
              .write(
                InventoryBalancesCompanion(quantityOnHandAtomic: Value(value)),
              );
          expect(
            (await h.tracking.orders.candidates()).first.suggestedAtomic,
            value >= 7 ? 0 : 7 - value,
          );
        }
        await expectLater(h.orders.save(review), throwsStateError);
        await (h.db.update(
          h.db.productVariants,
        )..where((t) => t.id.equals(c.variantId))).write(
          const ProductVariantsCompanion(targetStockAtomic: Value(null)),
        );
        expect((await h.tracking.orders.candidates()).first.suggestedAtomic, 0);
        expect(
          (await DriftSupplierOrderRepository(
            h.db,
          ).watchIssues().first).single.reason,
          'Falta objetivo',
        );
        await (h.db.update(h.db.products)
              ..where((t) => t.id.equals(c.productId)))
            .write(const ProductsCompanion(active: Value(false)));
        expect(await h.tracking.orders.candidates(), isEmpty);
      } finally {
        await h.dispose();
      }
    },
  );
}
