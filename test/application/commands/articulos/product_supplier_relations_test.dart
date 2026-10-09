import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/sync/payloads/proveedor_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/sale_mode.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_proveedor_precio.dart';
import 'package:pos_flutter/application/sync/projections/producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/precio_proveedor.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_preview_form.dart';

import '../../../support/product_supplier_harness.dart';
import '../../../support/supplier_contract_fixtures.dart';

const date = 1791331200000;
const unknownId = '00000000-0000-4000-8000-000000000099';

ProveedorVariante quote(String id, [int price = 0, int at = date]) =>
    ProveedorVariante(
      proveedorId: id,
      precioInformadoMenor: price,
      fechaInformadaMs: at,
    );

CrearArticuloVarianteCommand variant({
  String? name,
  List<ProveedorVariante>? suppliers,
  String price = '25',
  String? cost,
  String? unit,
  List<CrearArticuloRecipeComponentCommand> recipe = const [],
}) => CrearArticuloVarianteCommand.conProveedores(
  nombre: name,
  precioVenta: price,
  costoEstandar: cost,
  proveedores: suppliers,
  inventoryUnitId: unit,
  recipeComponents: recipe,
);

CrearArticuloCommand article(
  List<CrearArticuloVarianteCommand> variants, {
  String name = 'Café',
  SaleConfiguration sale = const UnitSaleConfiguration(),
}) => CrearArticuloCommand.conVariantes(
  nombre: name,
  variantes: variants,
  saleConfiguration: sale,
);

SyncEvent event(
  String id,
  String productId,
  String type,
  Map<String, Object?> payload, {
  int version = 1,
  int? sequence,
}) => SyncEvent(
  eventId: id,
  aggregateType: 'product',
  aggregateId: productId,
  eventType: type,
  deviceId: 'test',
  userId: 'test',
  createdAtLocal: DateTime.utc(2026),
  baseVersion: version,
  baseServerSequence: sequence,
  payload: payload,
);

void main() {
  late ProductSupplierHarness h;
  setUp(() => h = ProductSupplierHarness());
  tearDown(() => h.dispose());

  Future<ProductoProjection> create(
    List<CrearArticuloVarianteCommand> variants,
  ) async {
    await h.commands.crearArticulo(article(variants));
    return (await h.tracking.products.findProductById(
      h.appends.last.event.aggregateId,
    ))!;
  }

  Future<void> save(
    ProductoProjection p,
    List<CrearArticuloVarianteCommand> variants, {
    List<String?>? ids,
    String name = 'Café',
    String? base,
  }) async {
    final current = (await h.tracking.products.findProductById(p.id))!;
    await h.commands.actualizarArticulo(
      productId: p.id,
      baseEventId: base ?? current.lastEventId!,
      variantIds:
          ids ??
          (await h.tracking.products.snapshot(
            p.id,
          )).variantes.map((v) => v.id).toList(),
      command: article(variants, name: name, sale: current.saleConfiguration),
    );
  }

  test(
    'alta con variantes, proveedores compartidos, cero y listas canónicas inmutables',
    () async {
      final a = await h.supplier('A');
      final b = await h.supplier('B');
      final p = await create([
        variant(suppliers: [quote(b, 1234), quote(a)]),
        variant(
          name: 'Grande',
          suppliers: [quote(a, PrecioProveedor.maxUnidadMenor)],
        ),
      ]);
      final snapshot = await h.tracking.products.snapshot(p.id);
      expect(
        snapshot.variantes.first.proveedores!.map((s) => s.supplierId).toList(),
        [a, b]..sort(),
      );
      expect(
        snapshot.variantes.first.proveedores!
            .singleWhere((s) => s.supplierId == a)
            .quotedPriceMinor,
        0,
      );
      expect(
        snapshot.variantes.last.proveedores!.single.quotedPriceMinor,
        PrecioProveedor.maxUnidadMenor,
      );
      expect(snapshot.dependenciasProveedores, hasLength(2));
      expect(
        snapshot.dependenciasProveedores.every(
          (d) => d.dependsOnEventId == null,
        ),
        isTrue,
      );
      expect(
        () => snapshot.variantes.first.proveedores!.clear(),
        throwsUnsupportedError,
      );
      final detail = (await h.repository.obtenerDetalle(p.id))!;
      expect(detail.variantes.first.proveedores, hasLength(2));
      expect(
        () => detail.variantes.first.proveedores!.clear(),
        throwsUnsupportedError,
      );
      expect((await h.db.select(h.db.variantSuppliers).get()), hasLength(3));
      final refs = h.appends.last.refs;
      expect(
        refs.where((r) => r.refType == 'supplier').map((r) => r.refId).toSet(),
        {a, b},
      );
      expect(refs.where((r) => r.refType == 'variant_suppliers'), hasLength(2));
      final events = await h.tracking.storedEvents();
      expect(
        events.every(
          (e) =>
              e.deliveryStatus == 'not_required' &&
              e.applicationStatus == 'applied',
        ),
        isTrue,
      );
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
    },
  );

  test(
    'omitir relaciones al cambiar nombre, venta, costo y barcode conserva precios/fechas',
    () async {
      final a = await h.supplier('A');
      final p = await create([
        variant(suppliers: [quote(a, 1234)]),
      ]);
      final original = (await h.tracking.products.snapshot(
        p.id,
      )).variantes.single.proveedores;
      await save(p, [
        CrearArticuloVarianteCommand(
          nombre: null,
          precioVenta: '35',
          costoEstandar: '0',
          codigoBarras: '0123',
        ),
      ], name: 'Nuevo');
      final current = await h.tracking.products.snapshot(p.id);
      expect(
        ProductoProveedorPrecio.sameList(
          original,
          current.variantes.single.proveedores,
        ),
        isTrue,
      );
      expect(current.nombre, 'Nuevo');
      expect(current.variantes.single.precioVentaMenor, 3500);
      expect(current.variantes.single.costoEstandarMenor, 0);
      expect(current.variantes.single.codigoBarras, '0123');
      expect(await h.db.select(h.db.inventoryMovements).get(), isEmpty);
      final form = ArticuloPreviewForm.fromDetalle(
        (await h.repository.obtenerDetalle(p.id))!,
        const [],
      );
      expect(
        form.variantes.single.copyWith(precioVenta: '40').proveedores!.single,
        quote(a, 1234),
      );
    },
  );

  test(
    'precio sin cambios conserva fecha; precio nuevo conserva la fecha informada nueva',
    () async {
      final a = await h.supplier('A');
      final p = await create([
        variant(suppliers: [quote(a, 1234)]),
      ]);
      await save(p, [
        variant(suppliers: [quote(a, 1234, date + 1)]),
      ]);
      expect(
        (await h.tracking.products.snapshot(
          p.id,
        )).variantes.single.proveedores!.single.quotedAtMs,
        date,
      );
      await save(p, [
        variant(suppliers: [quote(a, 0, date + 2)]),
      ]);
      final current = (await h.tracking.products.snapshot(
        p.id,
      )).variantes.single.proveedores!.single;
      expect(current.quotedPriceMinor, 0);
      expect(current.quotedAtMs, date + 2);
    },
  );

  test(
    'retirar último proveedor deja [] y catálogo, refs y before conservan al retirado',
    () async {
      final a = await h.supplier('A');
      final p = await create([
        variant(suppliers: [quote(a)]),
      ]);
      await save(p, [variant(suppliers: [])]);
      final update = ProductoActualizadoPayload.fromJson(
        h.appends.last.event.payload,
      );
      expect(update.before.supplierIds, {a});
      expect(update.after.supplierIds, isEmpty);
      expect(update.after.variantes.single.proveedores, isEmpty);
      expect(update.after.dependenciasProveedores, isEmpty);
      expect(await h.db.select(h.db.variantSuppliers).get(), isEmpty);
      expect(await h.db.select(h.db.suppliers).get(), hasLength(1));
      expect(
        h.appends.last.refs.any(
          (r) =>
              r.refType == 'supplier' &&
              r.refId == a &&
              r.relationship == 'uses',
        ),
        isTrue,
      );
      expect(
        (await h.tracking.products.snapshot(p.id)).variantes.single.proveedores,
        isEmpty,
      );
      await save(p, [variant(price: '30')]);
      expect(
        (await h.tracking.products.snapshot(p.id)).variantes.single.proveedores,
        isEmpty,
      );
    },
  );

  test(
    'duplicates e inexistente fallan antes de producto, recursos o eventos parciales',
    () async {
      final a = await h.supplier('A');
      final priorEvents = await h.tracking.storedEvents();
      for (final suppliers in [
        [quote(a), quote(a)],
        [quote(unknownId)],
      ]) {
        await expectLater(
          Future.sync(
            () => h.commands.crearArticulo(
              article([
                variant(unit: InventoryUnitIds.piece, suppliers: suppliers),
              ]),
            ),
          ),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
        expect(
          (await h.tracking.storedEvents()).map((e) => e.eventId),
          priorEvents.map((e) => e.eventId),
        );
        expect(await h.db.select(h.db.products).get(), isEmpty);
        expect(await h.db.select(h.db.inventoryItems).get(), isEmpty);
        expect(await h.db.select(h.db.variantSuppliers).get(), isEmpty);
      }
    },
  );

  test(
    'edición inválida y base obsoleta conservan snapshot y bitácora',
    () async {
      final a = await h.supplier('A');
      final p = await create([
        variant(suppliers: [quote(a)]),
      ]);
      final original = await h.tracking.products.snapshot(p.id);
      final count = (await h.tracking.storedEvents()).length;
      await expectLater(
        save(p, [
          variant(suppliers: [quote(unknownId)]),
        ]),
        throwsStateError,
      );
      await expectLater(
        Future.sync(
          () => save(p, [
            variant(suppliers: [quote(a), quote(a)]),
          ]),
        ),
        throwsFormatException,
      );
      await expectLater(
        save(p, [variant()], base: 'obsoleto'),
        throwsStateError,
      );
      expect(
        ProductoActualizadoPayload.sameState(
          original,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
      expect(await h.tracking.storedEvents(), hasLength(count));
    },
  );

  test(
    'rollback después de alta revierte producto, variantes, relaciones y recurso',
    () async {
      final a = await h.supplier('A');
      h.failAfterProductApply = true;
      await expectLater(
        h.commands.crearArticulo(
          article([
            variant(unit: InventoryUnitIds.piece, suppliers: [quote(a)]),
          ]),
        ),
        throwsStateError,
      );
      expect(await h.db.select(h.db.products).get(), isEmpty);
      expect(await h.db.select(h.db.productVariants).get(), isEmpty);
      expect(await h.db.select(h.db.variantSuppliers).get(), isEmpty);
      expect(await h.db.select(h.db.inventoryItems).get(), isEmpty);
      expect(await h.tracking.storedEvents(), hasLength(1));
    },
  );

  test(
    'rollback tras edición conserva producto, listas y eventos exactamente',
    () async {
      final a = await h.supplier('A');
      final b = await h.supplier('B');
      final p = await create([
        variant(suppliers: [quote(a)]),
      ]);
      final original = await h.tracking.products.snapshot(p.id);
      final rows = await h.db.select(h.db.productVariants).get();
      final count = (await h.tracking.storedEvents()).length;
      h.failAfterProductApply = true;
      await expectLater(
        save(p, [
          variant(suppliers: [quote(b, 123)]),
        ], name: 'Error'),
        throwsStateError,
      );
      expect(
        ProductoActualizadoPayload.sameState(
          original,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
      expect(await h.db.select(h.db.productVariants).get(), rows);
      expect(await h.tracking.storedEvents(), hasLength(count));
    },
  );

  test(
    'idempotencia de alta y edición incluso después de cambiar sus listas',
    () async {
      final a = await h.supplier('A');
      final p = await create([
        variant(suppliers: [quote(a)]),
      ]);
      final creation = (await h.tracking.storedEvents()).last;
      await save(p, [variant(suppliers: [])]);
      final update = (await h.tracking.storedEvents()).last;
      final original = await h.tracking.products.snapshot(p.id);
      final product = await h.tracking.products.findProductById(p.id);
      await h.db.transaction(() async {
        await h.tracking.processor.apply(creation);
        await h.tracking.processor.apply(update);
      });
      expect(
        ProductoActualizadoPayload.sameState(
          original,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
      expect(
        (await h.tracking.products.findProductById(p.id))!.version,
        product!.version,
      );
      expect(await h.db.select(h.db.variantSuppliers).get(), isEmpty);
    },
  );

  test(
    'restauración fallback de snapshot completo recupera precio, fecha y versión',
    () async {
      final a = await h.supplier('A');
      final b = await h.supplier('B');
      final p = await create([
        variant(suppliers: [quote(a, 123)]),
      ]);
      final before = await h.tracking.products.snapshot(p.id);
      await save(p, [
        variant(suppliers: [quote(b, 456)]),
      ]);
      final update = (await h.tracking.storedEvents()).last;
      await h.db.transaction(
        () => h.tracking.products.applyUpdate(
          update,
          before,
          restore: true,
          baseEventId: p.lastEventId,
        ),
      );
      expect(
        ProductoActualizadoPayload.sameState(
          before,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
      expect(
        (await h.tracking.products.findProductById(p.id))!.version,
        p.version,
      );
      expect(
        (await h.tracking.products.findProductById(p.id))!.lastEventId,
        p.lastEventId,
      );
    },
  );

  test(
    'reordenar y retirar variante conserva listas inactivas; undo restaura todo',
    () async {
      final a = await h.supplier('A');
      final b = await h.supplier('B');
      final p = await create([
        variant(suppliers: [quote(a)]),
        variant(name: 'Grande', suppliers: [quote(b, 456)]),
      ]);
      final before = await h.tracking.products.snapshot(p.id);
      final originalRows = await h.db.select(h.db.productVariants).get();
      await save(p, [
        variant(name: 'Grande'),
        variant(),
      ], ids: before.variantes.reversed.map((v) => v.id).toList());
      final ordered = await h.tracking.products.snapshot(p.id);
      expect(ordered.variantes.first.proveedores!.single.supplierId, b);
      final base = (await h.tracking.products.findProductById(p.id))!;
      await save(
        p,
        [variant(name: 'Grande')],
        ids: [ordered.variantes.first.id],
      );
      final removed = (await h.tracking.products.findVariantById(
        before.variantes.first.id,
      ))!;
      expect(removed.active, isFalse);
      expect(
        await h.db.productoDao.obtenerProveedoresPorVariante(removed.id),
        hasLength(1),
      );
      expect(
        h.appends.last.refs.any(
          (r) => r.refType == 'variant_suppliers' && r.refId == removed.id,
        ),
        isTrue,
      );
      expect(
        h.appends.last.refs.any((r) => r.refType == 'supplier' && r.refId == a),
        isTrue,
      );
      final latest = (await h.tracking.storedEvents()).last;
      await h.db.transaction(
        () => h.tracking.products.applyUpdate(
          latest,
          ordered,
          restore: true,
          baseEventId: base.lastEventId,
        ),
      );
      expect(
        ProductoActualizadoPayload.sameState(
          ordered,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
      expect(await h.db.select(h.db.variantSuppliers).get(), hasLength(2));
      expect(originalRows, hasLength(2));
    },
  );

  test(
    'undo de DAO conserva relaciones de variantes previamente retiradas y retira añadidas',
    () async {
      final a = await h.supplier('A');
      final b = await h.supplier('B');
      final p = await create([
        variant(suppliers: [quote(a)]),
        variant(name: 'Grande', suppliers: [quote(b, 456)]),
      ]);
      final initial = await h.tracking.products.snapshot(p.id);
      await save(p, [variant()], ids: [initial.variantes.first.id]);
      final rows = await h.db.select(h.db.productVariants).get();
      final sets = await h.db.select(h.db.variantSuppliers).get();
      final current = (await h.tracking.products.findProductById(p.id))!;
      final before = await h.tracking.products.snapshot(p.id);
      await save(
        p,
        [
          variant(suppliers: []),
          variant(name: 'Nueva', suppliers: [quote(b)]),
        ],
        ids: [before.variantes.single.id, null],
      );
      final update = (await h.tracking.storedEvents()).last;
      // Snapshot saving is ordinarily used for pending changes; exercise the
      // same mechanism with isolated standalone data and its matching event ID.
      await h.db.transaction(() async {
        await h.tracking.products.applyUpdate(
          update,
          before,
          restore: true,
          baseEventId: current.lastEventId,
        );
        await h.db.productoDao.guardarRespaldoActualizacion(
          update.eventId,
          p.id,
        );
        await h.tracking.processor.apply(update);
      });
      await h.db.transaction(
        () => h.tracking.products.applyUpdate(
          update,
          before,
          restore: true,
          baseEventId: current.lastEventId,
        ),
      );
      expect(await h.db.select(h.db.productVariants).get(), rows);
      expect(
        await h.db.select(h.db.variantSuppliers).get(),
        unorderedEquals(sets),
      );
      expect(await h.db.select(h.db.productUpdateUndo).get(), isEmpty);
    },
  );

  test(
    'borrado del artículo conserva historial, referencias y permite restaurarlo',
    () async {
      final a = await h.supplier('A');
      final p = await create([
        variant(suppliers: [quote(a)]),
      ]);
      final before = await h.tracking.products.snapshot(p.id);
      await h.commands.eliminarArticulo(
        productId: p.id,
        baseEventId: p.lastEventId!,
      );
      final update = (await h.tracking.storedEvents()).last;
      expect(await h.repository.obtenerDetalle(p.id), isNull);
      expect(
        (await h.tracking.products.findVariantById(
          before.variantes.single.id,
        ))!.active,
        isFalse,
      );
      expect(await h.db.select(h.db.variantSuppliers).get(), hasLength(1));
      expect(await h.db.select(h.db.suppliers).get(), hasLength(1));
      expect(
        h.appends.last.refs.any((r) => r.refType == 'supplier' && r.refId == a),
        isTrue,
      );
      expect(
        h.appends.last.refs.any((r) => r.refType == 'variant_suppliers'),
        isTrue,
      );
      await h.db.transaction(
        () => h.tracking.products.applyUpdate(
          update,
          before,
          restore: true,
          baseEventId: p.lastEventId,
        ),
      );
      expect(
        ProductoActualizadoPayload.sameState(
          before,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
      await h.db.transaction(() => h.tracking.products.deleteProductById(p.id));
      expect(await h.db.select(h.db.variantSuppliers).get(), isEmpty);
      expect(await h.db.select(h.db.suppliers).get(), hasLength(1));
    },
  );

  test(
    'replay legado conserva omisión; nuevo comando parte de snapshot actual completo',
    () async {
      final legacy = ProductoCreadoPayload.fromJson(
        supplierFixture('producto_legado'),
      );
      final creation = event(
        'legacy-create',
        'legacy-product',
        ProductoCreadoPayload.eventType,
        legacy.toJson(),
      );
      const refs = [
        LocalEventRef.affects(refType: 'product', refId: 'legacy-product'),
      ];
      await h.events.appendAndApply(creation, refs: refs);
      final updated = ProductoCreadoPayload.simple(
        nombre: 'Legado editado',
        categoriaId: null,
        varianteId: legacy.variantes.single.id,
        precioVentaMenor: 3000,
      );
      final oldEdit = event(
        'legacy-edit',
        'legacy-product',
        ProductoActualizadoPayload.eventType,
        ProductoActualizadoPayload(
          baseEventId: creation.eventId,
          before: legacy,
          after: updated,
        ).toJson(),
      );
      await h.events.appendAndApply(oldEdit, refs: refs);
      expect(
        (await h.tracking.products.snapshot(
          'legacy-product',
        )).variantes.single.proveedores,
        isNull,
      );
      final a = await h.supplier('A');
      final p = (await h.tracking.products.findProductById('legacy-product'))!;
      await save(p, [
        variant(suppliers: [quote(a)]),
      ]);
      final newEdit = ProductoActualizadoPayload.fromJson(
        h.appends.last.event.payload,
      );
      expect(newEdit.before.nombre, 'Legado editado');
      expect(newEdit.before.variantes.single.precioVentaMenor, 3000);
      expect(newEdit.before.variantes.single.proveedores, isEmpty);
      expect(newEdit.after.variantes.single.proveedores!.single.supplierId, a);
      expect(newEdit.baseEventId, oldEdit.eventId);
    },
  );

  test(
    'restaurar primera edición moderna conserva snapshot completo vacío al leer',
    () async {
      final legacy = ProductoCreadoPayload.fromJson(
        supplierFixture('producto_legado'),
      );
      final creation = event(
        'legacy-root',
        'legacy-empty',
        ProductoCreadoPayload.eventType,
        legacy.toJson(),
      );
      await h.events.appendAndApply(
        creation,
        refs: const [
          LocalEventRef.affects(refType: 'product', refId: 'legacy-empty'),
        ],
      );
      final a = await h.supplier('A');
      final p = (await h.tracking.products.findProductById('legacy-empty'))!;
      await save(p, [
        variant(suppliers: [quote(a)]),
      ]);
      final update = (await h.tracking.storedEvents()).last;
      final before = ProductoActualizadoPayload.fromJson(update.payload).before;
      await h.db.transaction(
        () => h.tracking.products.applyUpdate(
          update,
          before,
          restore: true,
          baseEventId: p.lastEventId,
        ),
      );
      expect(
        ProductoActualizadoPayload.sameState(
          before,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
      expect(
        (await h.repository.obtenerDetalle(p.id))!.variantes.single.proveedores,
        isEmpty,
      );
      final history = await h.tracking.tracking.historyForVariant(
        before.variantes.single.id,
      );
      expect(history.currentState!.variantes.single.proveedores, isEmpty);
    },
  );

  for (final initiallyEmpty in [true, false]) {
    test(
      'base legada sobre estado conocido empty=$initiallyEmpty falla sin borrar',
      () async {
        final a = await h.supplier('A');
        final p = await create([
          variant(suppliers: initiallyEmpty ? [] : [quote(a)]),
        ]);
        final current = await h.tracking.products.snapshot(p.id);
        final legacy = ProductoCreadoPayload.simple(
          nombre: current.nombre,
          categoriaId: null,
          varianteId: current.variantes.single.id,
          precioVentaMenor: 2500,
        );
        final bad = event(
          'bad-base',
          p.id,
          ProductoActualizadoPayload.eventType,
          ProductoActualizadoPayload(
            baseEventId: p.lastEventId!,
            before: legacy,
            after: legacy,
          ).toJson(),
        );
        await expectLater(
          h.events.appendAndApply(
            bad,
            refs: [LocalEventRef.affects(refType: 'product', refId: p.id)],
          ),
          throwsStateError,
        );
        expect(
          ProductoActualizadoPayload.sameState(
            current,
            await h.tracking.products.snapshot(p.id),
          ),
          isTrue,
        );
        expect(await h.db.eventDao.obtenerEventoPorId('bad-base'), isNull);
      },
    );
  }

  test(
    'before conocido incorrecto, versión y secuencia fallan sin escrituras',
    () async {
      final a = await h.supplier('A');
      final p = await create([
        variant(suppliers: [quote(a, 123)]),
      ]);
      final current = await h.tracking.products.snapshot(p.id);
      final badJson =
          jsonDecode(jsonEncode(current.toJson())) as Map<String, dynamic>;
      (badJson['variants'] as List)
              .first['suppliers'][0]['quoted_price_minor'] =
          124;
      final bad = ProductoCreadoPayload.fromJson(
        Map<String, Object?>.from(badJson),
      );
      for (final scenario in ['before', 'version', 'sequence']) {
        final e = event(
          'bad-$scenario',
          p.id,
          ProductoActualizadoPayload.eventType,
          ProductoActualizadoPayload(
            baseEventId: p.lastEventId!,
            before: scenario == 'before' ? bad : current,
            after: current,
          ).toJson(),
          version: scenario == 'version' ? 99 : 1,
          sequence: scenario == 'sequence' ? 99 : null,
        );
        await expectLater(
          h.events.appendAndApply(
            e,
            refs: [LocalEventRef.affects(refType: 'product', refId: p.id)],
          ),
          throwsStateError,
        );
        expect(await h.db.eventDao.obtenerEventoPorId(e.eventId), isNull);
      }
      expect(
        ProductoActualizadoPayload.sameState(
          current,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
    },
  );

  test(
    'solo alta local pendiente agrega dependencia; not_required nunca se promueve',
    () async {
      final a = await h.supplier('A');
      final supplier = (await h.tracking.suppliers.findById(a))!;
      await h.db.eventDao.actualizarEstadoSincronizacion(
        supplier.createdEventId!,
        'pending',
      );
      final p = await create([
        variant(suppliers: [quote(a)]),
      ]);
      final payload = ProductoCreadoPayload.fromJson(
        h.appends.last.event.payload,
      );
      expect(
        payload.dependenciasProveedores.single.dependsOnEventId,
        supplier.createdEventId,
      );
      await h.db.eventDao.actualizarEstadoSincronizacion(
        supplier.createdEventId!,
        'not_required',
      );
      await save(p, [variant()]);
      final updated = ProductoActualizadoPayload.fromJson(
        h.appends.last.event.payload,
      );
      expect(
        updated.after.dependenciasProveedores.single.dependsOnEventId,
        isNull,
      );
      expect(
        (await h.db.eventDao.obtenerEventoPorId(
          supplier.createdEventId!,
        ))!.deliveryStatus,
        'not_required',
      );
      expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
    },
  );

  test(
    'lote inválido no escribe otros productos; lote válido construye [] explícito',
    () async {
      final a = await h.supplier('A');
      await expectLater(
        h.commands.crearArticulosLote([
          article([
            variant(suppliers: [quote(a)]),
          ]),
          article([
            variant(suppliers: [quote(unknownId)]),
          ]),
        ]),
        throwsStateError,
      );
      expect(await h.db.select(h.db.products).get(), isEmpty);
      expect(await h.tracking.storedEvents(), hasLength(1));
      await h.commands.crearArticulosLote([
        article([variant()]),
        article([variant()], name: 'B'),
      ]);
      final events = (await h.tracking.storedEvents()).where(
        (e) => e.aggregateType == 'product',
      );
      expect(events, hasLength(2));
      for (final e in events) {
        expect(
          ProductoCreadoPayload.fromJson(
            e.payload,
          ).variantes.single.proveedores,
          isEmpty,
        );
      }
    },
  );

  for (final tracking in ['none', 'direct', 'recipe']) {
    test(
      'proveedores coexisten con $tracking sin cambiar consumo o movimientos',
      () async {
        final a = await h.supplier('A');
        String? resource;
        if (tracking == 'recipe') {
          await h.tracking.inventoryCommands.crearRecurso(
            const CrearRecursoInventarioCommand(
              nombre: 'Ingrediente',
              defaultUnitId: InventoryUnitIds.piece,
            ),
          );
          resource = (await h.db.select(h.db.inventoryItems).get()).single.id;
        }
        final p = await create([
          variant(
            suppliers: [quote(a)],
            unit: tracking == 'direct' ? InventoryUnitIds.piece : null,
            recipe: resource == null
                ? []
                : [
                    CrearArticuloRecipeComponentCommand(
                      inventoryItemId: resource,
                      quantity: '2',
                    ),
                  ],
          ),
        ]);
        final before = await h.tracking.products.snapshot(p.id);
        final key = await h.tracking.products.consumptionConfigurationKey(
          before.variantes.single.id,
        );
        final movements = await h.db.select(h.db.inventoryMovements).get();
        await save(p, [
          variant(
            suppliers: [quote(a, 12, date + 1)],
            unit: tracking == 'direct' ? InventoryUnitIds.piece : null,
            recipe: resource == null
                ? []
                : [
                    CrearArticuloRecipeComponentCommand(
                      inventoryItemId: resource,
                      quantity: '2',
                    ),
                  ],
          ),
        ]);
        expect(
          await h.tracking.products.consumptionConfigurationKey(
            before.variantes.single.id,
          ),
          key,
        );
        expect(await h.db.select(h.db.inventoryMovements).get(), movements);
        expect(
          (await h.tracking.products.snapshot(
            p.id,
          )).variantes.single.precioVentaMenor,
          2500,
        );
      },
    );
  }

  test(
    'server_sync aplica conjunto vacío, valida proveedor y conserva refs',
    () async {
      h.tracking.config.update(
        h.tracking.config.config.copyWith(mode: AppMode.serverSync),
      );
      await expectLater(
        h.commands.crearArticulo(
          article([
            variant(suppliers: [quote(unknownId)]),
          ]),
        ),
        throwsStateError,
      );
      final p = await create([variant(suppliers: [])]);
      expect(
        (await h.tracking.products.snapshot(p.id)).variantes.single.proveedores,
        isEmpty,
      );
      expect(
        (await h.tracking.storedEvents()).single.deliveryStatus,
        'pending',
      );
      expect(
        (await h.db.select(h.db.eventRefs).get()).map((r) => r.refType),
        contains('variant_suppliers'),
      );
      await save(p, [variant(price: '30')]);
      final update = ProductoActualizadoPayload.fromJson(
        h.appends.last.event.payload,
      );
      expect(update.before.variantes.single.proveedores, isEmpty);
      expect(update.after.variantes.single.proveedores, isEmpty);
    },
  );

  for (final remote in [false, true]) {
    test(
      'handler aplica contrato nuevo pendiente/oficial remoto=$remote',
      () async {
        final state = ProductoCreadoPayload.fromJson(
          supplierFixture('producto_sin_proveedores'),
        );
        final e =
            event(
              'supported',
              'supported-product',
              ProductoCreadoPayload.eventType,
              state.toJson(),
            ).copyWith(
              deliveryStatus: remote ? 'delivered' : 'pending',
              serverSequence: remote ? 1 : null,
            );
        await h.db.transaction(() => h.tracking.processor.apply(e));
        expect(await h.db.select(h.db.products).get(), hasLength(1));
        expect(await h.db.select(h.db.variantSuppliers).get(), isEmpty);
      },
    );
  }

  test(
    'reapertura SQLite temporal conserva conjuntos vacíos conocidos y precios',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'pos_product_suppliers_',
      );
      final file = File('${directory.path}/pos.sqlite');
      final first = ProductSupplierHarness(
        database: AppDatabase.forTesting(NativeDatabase(file)),
      );
      String productId;
      try {
        final a = await first.supplier('A');
        await first.commands.crearArticulo(
          article([
            variant(suppliers: [quote(a, 123)]),
            variant(name: 'Vacío', suppliers: []),
          ]),
        );
        productId = first.appends.last.event.aggregateId;
        final legacy = ProductoCreadoPayload.fromJson(
          supplierFixture('producto_legado'),
        );
        final root = event(
          'legacy-reopen-root',
          'legacy-reopen',
          ProductoCreadoPayload.eventType,
          legacy.toJson(),
        );
        await first.events.appendAndApply(
          root,
          refs: const [
            LocalEventRef.affects(refType: 'product', refId: 'legacy-reopen'),
          ],
        );
        await first.commands.actualizarArticulo(
          productId: 'legacy-reopen',
          baseEventId: root.eventId,
          variantIds: [legacy.variantes.single.id],
          command: article([
            variant(suppliers: [quote(a)]),
          ]),
        );
        final update = (await first.tracking.storedEvents()).last;
        final before = ProductoActualizadoPayload.fromJson(
          update.payload,
        ).before;
        await first.db.transaction(
          () => first.tracking.products.applyUpdate(
            update,
            before,
            restore: true,
            baseEventId: root.eventId,
          ),
        );
      } finally {
        await first.dispose();
      }
      final second = ProductSupplierHarness(
        database: AppDatabase.forTesting(NativeDatabase(file)),
      );
      try {
        final snapshot = await second.tracking.products.snapshot(productId);
        expect(snapshot.variantes.first.proveedores!.single.quotedAtMs, date);
        expect(snapshot.variantes.last.proveedores, isEmpty);
        expect(
          (await second.repository.obtenerDetalle(
            productId,
          ))!.variantes.first.proveedores!.single.precioInformadoMenor,
          123,
        );
        expect(await second.db.select(second.db.eventRefs).get(), isEmpty);
        expect(
          (await second.tracking.products.snapshot(
            'legacy-reopen',
          )).variantes.single.proveedores,
          isEmpty,
        );
        expect(
          (await second.repository.obtenerDetalle(
            'legacy-reopen',
          ))!.variantes.single.proveedores,
          isEmpty,
        );
      } finally {
        await second.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'ediciones concurrentes de proveedores distintos conservan conflicto de agregado',
    () async {
      final a = await h.supplier('A');
      final b = await h.supplier('B');
      final p = await create([
        variant(suppliers: [quote(a), quote(b)]),
      ]);
      final capturedBase = p.lastEventId!;
      final results = await Future.wait([
        for (final suppliers in [
          [quote(a, 10), quote(b)],
          [quote(a), quote(b, 20)],
        ])
          save(
            p,
            [variant(suppliers: suppliers)],
            base: capturedBase,
          ).then<Object?>((_) => null, onError: (Object e) => e),
      ]);
      expect(results.whereType<StateError>(), hasLength(1));
      expect(results.where((r) => r == null), hasLength(1));
      final prices = (await h.tracking.products.snapshot(
        p.id,
      )).variantes.single.proveedores!;
      expect(prices.where((s) => s.quotedPriceMinor != 0), hasLength(1));
      expect((await h.tracking.products.findProductById(p.id))!.version, 2);
      expect(
        (await h.tracking.storedEvents()).where(
          (e) => e.eventType == ProductoActualizadoPayload.eventType,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'importación existente crea conjuntos vacíos y conserva proveedores de otros artículos',
    () async {
      final a = await h.supplier('A');
      final p = await create([
        variant(suppliers: [quote(a, 123)]),
      ]);
      final before = await h.tracking.products.snapshot(p.id);
      final importer = ArticuloImportBatchService(
        productoCommandService: h.commands,
        unidadInventarioRepository: UnidadInventarioRepositoryImpl(
          unitDao: h.db.unitDao,
        ),
      );
      final result = await importer.importar(const [
        ArticuloImportProducto(
          nombre: 'Importado',
          modoVenta: SaleMode.unit,
          variantes: [
            ArticuloImportVariante(
              linea: 2,
              sortOrder: 0,
              precioVentaMinor: 500,
            ),
          ],
        ),
      ], onProgress: (_) {});
      expect(result.productosImportados, 1);
      final created = ProductoCreadoPayload.fromJson(
        h.appends.last.event.payload,
      );
      expect(created.nombre, 'Importado');
      expect(created.variantes.single.proveedores, isEmpty);
      expect(
        ProductoActualizadoPayload.sameState(
          before,
          await h.tracking.products.snapshot(p.id),
        ),
        isTrue,
      );
    },
  );

  for (final name in ['producto_creado', 'producto_medido_con_receta']) {
    test(
      'fixture $name se proyecta y se restaura con los contratos de fases 1–2',
      () async {
        for (final id in [
          '00000000-0000-4000-8000-000000000002',
          '00000000-0000-4000-8000-000000000003',
        ]) {
          await h.events.appendAndApply(
            SyncEvent(
              eventId: const Uuid().v4(),
              aggregateType: 'supplier',
              aggregateId: id,
              eventType: ProveedorCreadoPayload.eventType,
              deviceId: 'test',
              userId: 'test',
              createdAtLocal: DateTime.utc(2026),
              baseVersion: 1,
              payload: supplierFixture('proveedor_creado'),
            ),
            refs: [LocalEventRef.affects(refType: 'supplier', refId: id)],
          );
        }
        if (name == 'producto_medido_con_receta') {
          final payload = RecursoInventarioCreadoPayload.create(
            inventoryItemId: '00000000-0000-4000-8000-000000000006',
            name: 'Ingrediente',
            defaultUnitId: InventoryUnitIds.kilogram,
          );
          await h.events.appendAndApply(
            SyncEvent(
              eventId: const Uuid().v4(),
              aggregateType: 'inventory_item',
              aggregateId: payload.inventoryItemId,
              eventType: RecursoInventarioCreadoPayload.eventType,
              deviceId: 'test',
              userId: 'test',
              createdAtLocal: DateTime.utc(2026),
              baseVersion: 1,
              payload: payload.toJson(),
            ),
            refs: [
              LocalEventRef.affects(
                refType: 'inventory_item',
                refId: payload.inventoryItemId,
              ),
            ],
          );
        }
        final fixture = ProductoCreadoPayload.fromJson(supplierFixture(name));
        final creation = event(
          'fixture-create',
          'fixture-product',
          ProductoCreadoPayload.eventType,
          fixture.toJson(),
        );
        await h.events.appendAndApply(
          creation,
          refs: const [
            LocalEventRef.affects(refType: 'product', refId: 'fixture-product'),
          ],
        );
        final current = await h.tracking.products.snapshot('fixture-product');
        expect(ProductoActualizadoPayload.sameState(fixture, current), isTrue);
        final update = event(
          'fixture-delete',
          'fixture-product',
          ProductoActualizadoPayload.eventType,
          ProductoActualizadoPayload(
            baseEventId: creation.eventId,
            before: current,
            after: current,
            deleteProduct: true,
          ).toJson(),
        );
        await h.events.appendAndApply(
          update,
          refs: const [
            LocalEventRef.affects(refType: 'product', refId: 'fixture-product'),
          ],
        );
        await h.db.transaction(
          () => h.tracking.products.applyUpdate(
            update,
            current,
            restore: true,
            baseEventId: creation.eventId,
          ),
        );
        expect(
          ProductoActualizadoPayload.sameState(
            fixture,
            await h.tracking.products.snapshot('fixture-product'),
          ),
          isTrue,
        );
      },
    );
  }

  final invalidFields = <(String, Object?)>[
    ('quoted_price_minor', -1),
    ('quoted_price_minor', 9007199254740992),
    ('quoted_price_minor', 1.5),
    ('quoted_price_minor', ''),
    ('quoted_price_minor', null),
    ('quoted_at_ms', 0),
    ('quoted_at_ms', 9007199254740992),
    ('quoted_at_ms', 1.5),
    ('quoted_at_ms', '2026-10-07'),
    ('quoted_at_ms', null),
    ('supplier_id', 'invalid'),
  ];
  for (var index = 0; index < invalidFields.length; index++) {
    final (field, value) = invalidFields[index];
    test(
      'payload inválido $field=$value revierte evento sin proyección parcial',
      () async {
        final data = supplierFixture('producto_creado');
        final variants = data['variants'] as List;
        (variants.first['suppliers'] as List).first[field] = value;
        await expectLater(
          h.events.appendAndApply(
            event(
              'invalid-$index',
              'invalid-product',
              ProductoCreadoPayload.eventType,
              data,
            ),
            refs: const [
              LocalEventRef.affects(
                refType: 'product',
                refId: 'invalid-product',
              ),
            ],
          ),
          throwsFormatException,
        );
        expect(await h.tracking.storedEvents(), isEmpty);
        expect(await h.db.select(h.db.products).get(), isEmpty);
        expect(await h.db.select(h.db.variantSuppliers).get(), isEmpty);
      },
    );
  }

  for (final value in [-1, 9007199254740992]) {
    test(
      'dominio rechaza precio inválido $value',
      () => expect(() => quote(unknownId, value), throwsFormatException),
    );
  }
  for (final value in [0, -1, 9007199254740992]) {
    test(
      'dominio rechaza fecha inválida $value',
      () => expect(() => quote(unknownId, 0, value), throwsFormatException),
    );
  }
  test(
    'dominio canonical copia lista, normaliza UUID y rechaza duplicados',
    () {
      final values = [quote('  ${unknownId.toUpperCase()}  ')];
      final canonical = ProveedorVariante.canonical(values)!;
      values.clear();
      expect(canonical.single.proveedorId, unknownId);
      expect(() => canonical.clear(), throwsUnsupportedError);
      expect(
        () => ProveedorVariante.canonical([quote(unknownId), quote(unknownId)]),
        throwsFormatException,
      );
      expect(() => quote('invalid'), throwsFormatException);
    },
  );
  test('comando copia captura y conserva vacío explícito y ausencia', () {
    final input = [quote(unknownId)];
    final command = variant(suppliers: input);
    input.clear();
    expect(command.proveedores!.single.proveedorId, unknownId);
    expect(() => command.proveedores!.clear(), throwsUnsupportedError);
    expect(variant(suppliers: []).proveedores, isEmpty);
    expect(variant().proveedores, isNull);
  });
}
