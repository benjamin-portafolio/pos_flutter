import 'package:pos_flutter/application/commands/proveedores/crear_proveedor_command.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_variante_csv_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';
import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/catalogo_csv_v2_fixture.dart';

void main() {
  for (final mode in AppMode.values) {
    test(
      '${mode.name}: undo retira variante nueva seleccionada y creación rechazada',
      () async {
        final h = ProductSupplierHarness(mode: mode);
        try {
          final supplier = await h.supplier('Proveedor');
          final pair = ProveedorVariante(
            proveedorId: supplier,
            precioInformadoMenor: 0,
            fechaInformadaMs: 100,
          );
          CrearArticuloVarianteCommand variant(String? name) =>
              CrearArticuloVarianteCommand.conProveedores(
                nombre: name,
                precioVenta: '10',
                costoEstandar: null,
                proveedores: [pair],
                currentSupplier: CambioExplicito.establecer(supplier),
              );
          await h.commands.crearArticulo(
            CrearArticuloCommand.conVariantes(
              nombre: 'Undo seleccionado',
              variantes: [variant('Original')],
            ),
          );
          final id = h.appends.last.event.aggregateId;
          final creation = (await h.tracking.history.eventById(
            h.appends.last.event.eventId,
          ))!;
          final before = await h.tracking.products.snapshot(id);
          final product = (await h.tracking.products.findProductById(id))!;
          await h.commands.actualizarArticulo(
            productId: id,
            baseEventId: product.lastEventId!,
            variantIds: [before.variantes.single.id, null],
            command: CrearArticuloCommand.conVariantes(
              nombre: before.nombre,
              variantes: [variant('Original'), variant('Nueva')],
            ),
          );
          final update = (await h.tracking.history.eventById(
            h.appends.last.event.eventId,
          ))!;
          await h.db.transaction(
            () => h.tracking.cleaner.hideConflictProjection(update),
          );
          expect(
            (await h.tracking.products.snapshot(id)).toJson(),
            before.toJson(),
          );
          await h.db.transaction(
            () => h.tracking.cleaner.hideConflictProjection(creation),
          );
          expect(await h.tracking.products.findProductById(id), isNull);
        } finally {
          await h.dispose();
        }
      },
    );
    for (final measured in [false, true]) {
      test(
        '${mode.name} medido=$measured: persistir/reabrir, conservar, cero, null, selección, undo y sin stock',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'replenishment-s2-',
          );
          final file = File('${temp.path}/db.sqlite');
          var h = ProductSupplierHarness(
            database: AppDatabase.forTesting(NativeDatabase(file)),
            mode: mode,
          );
          try {
            final supplier = await h.supplier('Proveedor');
            final other = await h.supplier('Alternativo');
            final pairs = [
              for (final id in [supplier, other])
                ProveedorVariante(
                  proveedorId: id,
                  precioInformadoMenor: 0,
                  fechaInformadaMs: 100,
                ),
            ];
            await h.commands.crearArticulo(
              CrearArticuloCommand.conVariantes(
                nombre: 'Producto',
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
                    minimumStock: const CambioExplicito.establecer('1'),
                    proveedores: pairs,
                  ),
                ],
              ),
            );
            final id = h.appends.last.event.aggregateId;
            Future<ProductoCreadoPayload> state() =>
                h.tracking.products.snapshot(id);
            final balances = (await h.db.select(h.db.inventoryBalances).get())
                .map((r) => r.toJson())
                .toList();
            final movements = (await h.db.select(h.db.inventoryMovements).get())
                .map((r) => r.toJson())
                .toList();
            final initial = await state();
            Future<void> save({
              CambioExplicito<String?> target =
                  const CambioExplicito.conservar(),
              CambioExplicito<String?> selected =
                  const CambioExplicito.conservar(),
              List<ProveedorVariante>? suppliers,
              String? base,
              bool tracking = true,
            }) async {
              final s = await state();
              await h.commands.actualizarArticulo(
                productId: id,
                baseEventId:
                    base ??
                    (await h.tracking.products.findProductById(
                      id,
                    ))!.lastEventId!,
                variantIds: [s.variantes.single.id],
                command: CrearArticuloCommand.conVariantes(
                  nombre: s.nombre,
                  saleConfiguration: s.saleConfiguration,
                  variantes: [
                    CrearArticuloVarianteCommand.conProveedores(
                      nombre: null,
                      precioVenta: '10',
                      costoEstandar: null,
                      inventoryUnitId: tracking
                          ? (measured
                                ? InventoryUnitIds.kilogram
                                : InventoryUnitIds.piece)
                          : null,
                      proveedores: suppliers,
                      targetStock: target,
                      currentSupplier: selected,
                    ),
                  ],
                ),
              );
            }

            await save(
              target: CambioExplicito.establecer(measured ? '1,5' : '7'),
              selected: CambioExplicito.establecer(supplier),
            );
            var v = (await state()).variantes.single;
            expect(v.replenishment.targetAtomic, measured ? 1500 : 7);
            expect(v.replenishment.supplierId, supplier);
            expect(v.minimumStockAtomic, measured ? 1000 : 1);
            final csv = ArticuloCatalogCsv.catalogo(
              await h.db.productoDao.watchProductosListado().first,
            );
            final csvReview = await ArticuloImportPreparationService(
              parser: const ArticuloImportCsv(),
              reader: DriftArticuloImportCatalogReader(h.db),
            ).preparar(csv);
            expect(csvReview.errores, isEmpty);
            expect(csvReview.productosConCambios, isEmpty);
            final count = (await h.db.select(h.db.events).get()).length;
            await save();
            await save(
              target: CambioExplicito.establecer(measured ? '1.5' : '7'),
              selected: CambioExplicito.establecer(supplier),
            );
            expect((await h.db.select(h.db.events).get()).length, count);
            for (final invalid in [
              '-1',
              'NaN',
              '9007199254740992',
              measured ? '1.0001' : '1.5',
            ]) {
              await expectLater(
                save(target: CambioExplicito.establecer(invalid)),
                throwsFormatException,
              );
            }
            await expectLater(
              save(suppliers: [pairs.last]),
              throwsA(isA<Exception>()),
            );
            expect(
              (await state()).variantes.single.replenishment.supplierId,
              supplier,
            );
            await save(
              selected: CambioExplicito.establecer(other),
              suppliers: [pairs.last],
            );
            final failed = (await h.tracking.history.eventById(
              h.appends.last.event.eventId,
            ))!;
            await h.db.transaction(
              () => h.tracking.cleaner.hideConflictProjection(failed),
            );
            expect(
              (await state()).variantes.single.replenishment.supplierId,
              supplier,
            );
            expect((await state()).variantes.single.proveedores, hasLength(2));
            // A legacy CSV command touches commercial fields and knows neither new field.
            var p = (await h.tracking.products.findProductById(id))!;
            await h.commands.actualizarArticuloDesdeCsv(
              ActualizarArticuloCsvCommand(
                productId: id,
                baseEventId: p.lastEventId!,
                nombre: 'Renombrado',
                categoriaId: null,
                variantes: [
                  ActualizarArticuloVarianteCsvCommand(
                    variantId: v.id,
                    nombre: null,
                    precioVentaMinor: 1100,
                    precioCosteMinor: null,
                    codigoBarras: '001',
                  ),
                ],
              ),
            );
            expect(
              (await state()).variantes.single.replenishment.targetAtomic,
              measured ? 1500 : 7,
            );
            p = (await h.tracking.products.findProductById(id))!;
            await h.commands.asignarCodigoBarrasVariante(
              AsignarCodigoBarrasVarianteCommand(
                productId: id,
                variantId: v.id,
                baseEventId: p.lastEventId!,
                codigoBarras: '002',
              ),
            );
            expect(
              (await state()).variantes.single.replenishment.supplierId,
              supplier,
            );
            // An old snapshot omits the fields in both states; receiver must preserve them.
            p = (await h.tracking.products.findProductById(id))!;
            final before = (await state()).toJson();
            for (final row in before['variants'] as List) {
              (row as Map).remove('current_supplier_id');
              row.remove('target_stock_atomic');
            }
            final old = ProductoCreadoPayload.fromJson(before);
            expect(
              ProductoActualizadoPayload.sameEditingBase(await state(), old),
              isTrue,
            );
            final event = h.appends.last.event;
            final payload = ProductoActualizadoPayload(
              baseEventId: p.lastEventId!,
              before: old,
              after: old,
            );
            await h.db.transaction(
              () => h.tracking.products.applyUpdate(
                event.copyWith(
                  eventId: 'legacy-update',
                  baseVersion: p.version,
                  payload: payload.toJson(),
                ),
                old,
              ),
            );
            expect(
              (await state()).variantes.single.replenishment.targetAtomic,
              measured ? 1500 : 7,
            );
            // Return to the command path with the physical base just installed.
            await save(target: const CambioExplicito.establecer('0'));
            expect(
              (await state()).variantes.single.replenishment.targetAtomic,
              0,
            );
            await expectLater(
              save(base: initial.variantes.single.id),
              throwsStateError,
            );
            // Dormant configuration survives tracking removal.
            await save(tracking: false);
            expect(
              (await state()).variantes.single.replenishment.targetAtomic,
              0,
            );
            await save(
              tracking: false,
              selected: const CambioExplicito.establecer(null),
            );
            expect(
              (await state()).variantes.single.replenishment.supplierId,
              isNull,
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
            expect(
              await h.db.select(h.db.eventRefs).get(),
              mode == AppMode.standalone ? isEmpty : isNotEmpty,
            );
            expect(
              (await h.db.select(h.db.events).get())
                  .map((r) => r.deliveryStatus)
                  .toSet(),
              mode == AppMode.standalone ? {'not_required'} : {'pending'},
            );
            await h.dispose();
            h = ProductSupplierHarness(
              database: AppDatabase.forTesting(NativeDatabase(file)),
              mode: mode,
            );
            final reopened = (await h.repository.obtenerDetalle(
              id,
            ))!.variantes.single;
            expect(reopened.targetStockAtomic, 0);
            expect(reopened.currentSupplierId, isNull);
          } finally {
            await h.dispose();
            await temp.delete(recursive: true);
          }
        },
      );
    }
    test(
      '${mode.name}: CSV v2 exportar/importar y errores previos al guardado',
      () async {
        final h = ProductSupplierHarness(mode: mode);
        try {
          final supplier = await h.supplier('Proveedor');
          await h.supplierCommands.crearProveedor(
            const CrearProveedorCommand(nombre: 'Proveedor'),
          );
          final duplicateNameId = h.appends.last.event.aggregateId;

          await h.commands.crearArticulo(
            CrearArticuloCommand.conVariantes(
              nombre: 'CSV',
              variantes: [
                CrearArticuloVarianteCommand.conProveedores(
                  nombre: null,
                  precioVenta: '10',
                  costoEstandar: null,
                  inventoryUnitId: InventoryUnitIds.piece,
                  initialStockQuantity: '3',
                  proveedores: [
                    ProveedorVariante(
                      proveedorId: supplier,
                      precioInformadoMenor: 0,
                      fechaInformadaMs: 100,
                    ),
                  ],
                  currentSupplier: CambioExplicito.establecer(supplier),
                  targetStock: const CambioExplicito.establecer('0'),
                ),
              ],
            ),
          );
          final export = catalogoCsvV2Fixture(
            await h.db.productoDao.watchProductosListado().first,
          );
          final preparation = ArticuloImportPreparationService(
            parser: const ArticuloImportCsv(),
            reader: DriftArticuloImportCatalogReader(h.db),
          );
          final report = await preparation.preparar(export);
          expect(report.errores, isEmpty);
          expect(report.productosConCambios, isEmpty);
          expect(export, contains('target_stock_atomic'));
          var rows = export
              .trim()
              .split('\n')
              .map((r) => r.split(','))
              .toList();
          expect(rows.first, hasLength(22));
          rows.last[19] = '7';
          var changed = await preparation.preparar(
            rows.map((r) => r.join(',')).join('\n'),
          );
          expect(changed.errores, isEmpty);
          expect(
            changed
                .productosConCambios
                .single
                .variantes
                .single
                .replenishment
                .targetAtomic,
            7,
          );
          final imported =
              await ArticuloImportBatchService(
                productoCommandService: h.commands,
                unidadInventarioRepository: UnidadInventarioRepositoryImpl(
                  unitDao: h.db.unitDao,
                ),
              ).importar(
                [],
                actualizaciones: changed.productosConCambios,
                onProgress: (_) {},
              );
          expect(imported.productosFallidos, 0);
          expect(
            (await h.db.select(h.db.productVariants).get())
                .single
                .targetStockAtomic,
            7,
          );
          final reexport = catalogoCsvV2Fixture(
            await h.db.productoDao.watchProductosListado().first,
          );
          expect(
            (await preparation.preparar(reexport)).productosConCambios,
            isEmpty,
          );
          rows.last[20] = InventoryUnitIds.kilogram;
          changed = await preparation.preparar(
            rows.map((r) => r.join(',')).join('\n'),
          );
          expect(changed.errores, isNotEmpty);
          rows.last[20] = InventoryUnitIds.piece;
          rows.last[17] = duplicateNameId;
          changed = await preparation.preparar(
            rows.map((r) => r.join(',')).join('\n'),
          );
          expect(
            changed.errores.any((e) => e.motivo.contains('relación')),
            isTrue,
          );
        } finally {
          await h.dispose();
        }
      },
    );
  }
}
