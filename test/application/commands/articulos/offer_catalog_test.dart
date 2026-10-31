import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_variante_csv_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/edicion_masiva/operacion_edicion_masiva.dart';
import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/borrador_edicion_masiva.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/recepcion_masiva_fixture.dart';

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late ProductSupplierHarness h;
      setUp(() => h = ProductSupplierHarness(mode: mode));
      tearDown(() => h.dispose());
      Future<String> create() async {
        await h.commands.crearArticulo(
          const CrearArticuloCommand.conVariantes(
            nombre: 'Oferta',
            variantes: [
              CrearArticuloVarianteCommand(
                nombre: null,
                precioVenta: '20',
                costoEstandar: '3',
                offerPrice: CambioExplicito.establecer('15'),
                inventoryUnitId: InventoryUnitIds.piece,
                initialStockQuantity: '6',
              ),
            ],
          ),
        );
        return h.appends.last.event.aggregateId;
      }

      Future<void> save(
        String id, {
        CambioExplicito<String?> oferta = const CambioExplicito.conservar(),
        String normal = '20',
        CambioExplicito<String?> minimum = const CambioExplicito.conservar(),
      }) async {
        final s = await h.tracking.products.snapshot(id);
        final p = (await h.tracking.products.findProductById(id))!;
        await h.commands.actualizarArticulo(
          productId: id,
          baseEventId: p.lastEventId!,
          variantIds: s.variantes.map((v) => v.id).toList(),
          command: CrearArticuloCommand.conVariantes(
            nombre: 'Oferta editada',
            variantes: [
              CrearArticuloVarianteCommand(
                nombre: null,
                precioVenta: normal,
                costoEstandar: '3',
                offerPrice: oferta,
                inventoryUnitId: InventoryUnitIds.piece,
                minimumStock: minimum,
              ),
            ],
          ),
        );
      }

      Future<int?> offer(String id) async =>
          (await h.tracking.products.snapshot(
            id,
          )).variantes.single.offerPriceMinor;
      test(
        'alta/cambio/retiro, repositorio, inventario y refs por modo',
        () async {
          final id = await create();
          final first = await fotoRecepcion(h.db);
          final v = (await h.tracking.products.snapshot(id)).variantes.single;
          final key = await h.tracking.products.consumptionConfigurationKey(
            v.id,
          );
          expect(await offer(id), 1500);
          expect(
            (await h.repository.obtenerDetalle(
              id,
            ))!.variantes.single.offerPriceMinor,
            1500,
          );
          expect(
            (await h.repository.watchArticulos().first)
                .single
                .variantesActivas
                .single
                .offerPriceMinor,
            1500,
          );
          await save(id, oferta: const CambioExplicito.establecer('12.34'));
          await save(id);
          expect(await offer(id), 1234);
          await save(id, minimum: const CambioExplicito.establecer('3'));
          expect(await offer(id), 1234);
          expect(
            (await h.tracking.products.snapshot(
              id,
            )).variantes.single.minimumStockAtomic,
            3,
          );
          await h.commands.asignarCodigoBarrasVariante(
            AsignarCodigoBarrasVarianteCommand(
              productId: id,
              variantId: v.id,
              baseEventId: (await h.tracking.products.findProductById(
                id,
              ))!.lastEventId!,
              codigoBarras: '00123',
            ),
          );
          expect(await offer(id), 1234);
          await save(id, oferta: const CambioExplicito.establecer(null));
          expect(await offer(id), isNull);
          expect(
            (await h.tracking.products.snapshot(id)).knowsOfferPrice,
            isTrue,
          );
          final last = await fotoRecepcion(h.db);
          for (final t in [
            'inventory_items',
            'inventory_balances',
            'inventory_movements',
            'recipes',
          ]) {
            expect(last[t], first[t], reason: t);
          }
          expect(
            await h.tracking.products.consumptionConfigurationKey(v.id),
            key,
          );
          expect(
            (await h.db.select(h.db.productVariants).get())
                .single
                .standardCostMinor,
            300,
          );
          expect(
            last['event_refs'],
            mode == AppMode.standalone ? isEmpty : isNotEmpty,
          );
          final events = await h.tracking.storedEvents();
          expect(
            events.every(
              (e) =>
                  e.deliveryStatus ==
                  (mode == AppMode.standalone ? 'not_required' : 'pending'),
            ),
            isTrue,
          );
        },
      );
      test(
        'N1 y decimales inválidos rechazan sin escritura, también normal posterior',
        () async {
          final id = await create();
          final before = await fotoRecepcion(h.db);
          for (final input in [
            '0',
            '-1',
            '1.001',
            'NaN',
            '90071992547409.92',
            '99999999999999999999999999999999999',
          ]) {
            await expectLater(
              save(id, oferta: CambioExplicito.establecer(input)),
              throwsArgumentError,
            );
            expect(await fotoRecepcion(h.db), before);
          }
          await expectLater(save(id, normal: '14'), throwsFormatException);
          expect(await fotoRecepcion(h.db), before);
          await save(
            id,
            normal: '14',
            oferta: const CambioExplicito.establecer(null),
          );
          expect(await offer(id), isNull);
        },
      );
      test(
        'CSV antiguo conserva y nuevo establece/retira con revisión real e idempotencia',
        () async {
          final id = await create();
          final reader = DriftArticuloImportCatalogReader(h.db);
          final preparation = ArticuloImportPreparationService(
            parser: const ArticuloImportCsv(),
            reader: reader,
          );
          final batch = ArticuloImportBatchService(
            productoCommandService: h.commands,
            unidadInventarioRepository: UnidadInventarioRepositoryImpl(
              unitDao: h.db.unitDao,
            ),
          );
          Future<void> run(String csv) async {
            final report = await preparation.preparar(csv);
            expect(report.errores, isEmpty);
            final result = await batch.importar(
              report.productos,
              actualizaciones: report.productosConCambios,
              omitidos: report.productosSinCambios,
              onProgress: (_) {},
            );
            expect(result.productosFallidos, 0);
          }

          final exported = ArticuloCatalogCsv.catalogo(
            await h.db.productoDao.watchProductosListado().first,
          );
          final rows = exported
              .trim()
              .split('\n')
              .map((r) => r.split(','))
              .toList();
          expect(rows.last.sublist(12), ['15.00', 'establecer']);
          final old = [
            rows.first.take(12).join(','),
            [
              ...rows.last.take(7),
              '21.00',
              ...rows.last.sublist(8, 12),
            ].join(','),
          ].join('\n');
          await run(old);
          expect(await offer(id), 1500);
          rows.last[7] = '21.00';
          rows.last[12] = '13.00';
          await run(rows.map((r) => r.join(',')).join('\n'));
          expect(await offer(id), 1300);
          final count = (await h.tracking.storedEvents()).length;
          await run(rows.map((r) => r.join(',')).join('\n'));
          expect((await h.tracking.storedEvents()).length, count);
          rows.last[12] = '';
          rows.last[13] = 'retirar';
          await run(rows.map((r) => r.join(',')).join('\n'));
          expect(await offer(id), isNull);
        },
      );
      test(
        'masiva revisión, diario, reintento aplicado y recuperación conservan retiro',
        () async {
          final id = await create();
          final catalog = DriftCatalogoEdicionMasiva(h.db);
          final key = (await catalog.buscar()).single.clave;
          final draft = BorradorEdicionMasiva(catalogo: catalog);
          await draft.editarOferta(key, const CambioExplicito.establecer('11'));
          final review = await draft.prepararRevision();
          expect(review.cambios.single.oferta.valor, 1100);
          final op = OperacionEdicionMasiva.confirmada(
            batchId: 'offer-batch',
            modo: mode,
            cambios: review.cambios,
          );
          final service = coordinadorRecepcion(h);
          await service.confirmar(batchId: op.batchId, cambios: op.cambios);
          final first = await service.ejecutar(op);
          expect(first.catalogEventId, isNotNull);
          expect(await offer(id), 1100);
          final before = await fotoRecepcion(h.db);
          expect(
            (await service.ejecutar(
              OperacionEdicionMasiva.fromJson(op.intencionJson),
            )).catalogEventId,
            isNotNull,
          );
          expect(await fotoRecepcion(h.db), before);
          final remove = BorradorEdicionMasiva(catalogo: catalog);
          await remove.editarOferta(
            key,
            const CambioExplicito.establecer(null),
          );
          final next = OperacionEdicionMasiva.confirmada(
            batchId: 'offer-remove',
            modo: mode,
            cambios: (await remove.prepararRevision()).cambios,
          );
          expect(
            (jsonDecode(next.intencionJson)['changes'] as List).single
                .containsKey('offer_minor'),
            isTrue,
          );
          final recovered = BorradorEdicionMasiva(catalogo: catalog);
          await recovered.recuperar([
            OperacionEdicionMasiva.fromJson(next.intencionJson),
          ]);
          expect(
            (await recovered.prepararRevision()).cambios.single.oferta.valor,
            isNull,
          );
          await service.confirmar(batchId: next.batchId, cambios: next.cambios);
          expect((await service.ejecutar(next)).catalogEventId, isNotNull);
          expect(await offer(id), isNull);
        },
      );
      test(
        'proveedores/precios informados y receta conservan oferta en snapshots completos',
        () async {
          await h.tracking.inventoryCommands.crearRecurso(
            const CrearRecursoInventarioCommand(
              nombre: 'Ingrediente',
              defaultUnitId: InventoryUnitIds.piece,
              quantityDeltaAtomic: 20,
            ),
          );
          final resource =
              (await h.db.select(h.db.inventoryItems).get()).single.id;
          final supplier = await h.supplier('Proveedor');
          await h.commands.crearArticulo(
            CrearArticuloCommand.conVariantes(
              nombre: 'Receta con oferta',
              variantes: [
                CrearArticuloVarianteCommand(
                  nombre: null,
                  precioVenta: '20',
                  costoEstandar: '3',
                  offerPrice: const CambioExplicito.establecer('15'),
                  recipeComponents: [
                    CrearArticuloRecipeComponentCommand(
                      inventoryItemId: resource,
                      quantity: '1',
                    ),
                  ],
                ),
              ],
            ),
          );
          final id = h.appends.last.event.aggregateId;
          for (final quantity in ['1', '2']) {
            final state = await h.tracking.products.snapshot(id);
            await h.commands.actualizarArticulo(
              productId: id,
              baseEventId: (await h.tracking.products.findProductById(
                id,
              ))!.lastEventId!,
              variantIds: state.variantes.map((v) => v.id).toList(),
              command: CrearArticuloCommand.conVariantes(
                nombre: state.nombre,
                variantes: [
                  CrearArticuloVarianteCommand.conProveedores(
                    nombre: null,
                    precioVenta: '20',
                    costoEstandar: '3',
                    proveedores: [
                      ProveedorVariante(
                        proveedorId: supplier,
                        precioInformadoMenor: 250,
                        fechaInformadaMs: 1000,
                      ),
                    ],
                    recipeComponents: [
                      CrearArticuloRecipeComponentCommand(
                        inventoryItemId: resource,
                        quantity: quantity,
                      ),
                    ],
                  ),
                ],
              ),
            );
            final actual = (await h.tracking.products.snapshot(
              id,
            )).variantes.single;
            expect(actual.offerPriceMinor, 1500);
            expect(actual.costoEstandarMenor, 300);
            expect(actual.proveedores!.single.quotedPriceMinor, 250);
            expect(
              actual.componentesReceta.single.quantityAtomic,
              int.parse(quantity),
            );
          }
          expect(
            (await h.db.select(h.db.inventoryBalances).get())
                .single
                .quantityOnHandAtomic,
            20,
          );
        },
      );
      test(
        'diario en disco reabre intención y resultado con oferta/retiro sin duplicar',
        () async {
          final dir = await Directory.systemTemp.createTemp('offer-journal-');
          addTearDown(() => dir.delete(recursive: true));
          await h.dispose();
          h = ProductSupplierHarness(
            mode: mode,
            database: AppDatabase.forTesting(
              NativeDatabase(File('${dir.path}/catalog.sqlite')),
            ),
          );
          final id = await create();
          final draft = BorradorEdicionMasiva(
            catalogo: DriftCatalogoEdicionMasiva(h.db),
          );
          final key = (await DriftCatalogoEdicionMasiva(
            h.db,
          ).buscar()).single.clave;
          await draft.editarOferta(key, const CambioExplicito.establecer(null));
          final service = coordinadorRecepcion(h);
          final op = (await service.confirmar(
            batchId: 'disk-offer',
            cambios: (await draft.prepararRevision()).cambios,
          )).single;
          await h.dispose();
          h = ProductSupplierHarness(
            mode: mode,
            database: AppDatabase.forTesting(
              NativeDatabase(File('${dir.path}/catalog.sqlite')),
            ),
          );
          final reopened = coordinadorRecepcion(h);
          final recovered = (await reopened.registros()).single.operacion;
          expect(recovered.intencionJson, op.intencionJson);
          final result = await reopened.ejecutar(recovered);
          expect(await offer(id), isNull);
          final photo = await fotoRecepcion(h.db);
          await h.dispose();
          h = ProductSupplierHarness(
            mode: mode,
            database: AppDatabase.forTesting(
              NativeDatabase(File('${dir.path}/catalog.sqlite')),
            ),
          );
          expect(
            (await coordinadorRecepcion(h).ejecutar(op)).json,
            result.json,
          );
          expect(await fotoRecepcion(h.db), photo);
        },
      );
      test(
        'CSV acciones vacías, contradictorias e importes inválidos no escriben al revisar',
        () async {
          await create();
          final exported = ArticuloCatalogCsv.catalogo(
            await h.db.productoDao.watchProductosListado().first,
          );
          final source = exported
              .trim()
              .split('\n')
              .map((r) => r.split(','))
              .toList();
          final before = await fotoRecepcion(h.db);
          final preparation = ArticuloImportPreparationService(
            parser: const ArticuloImportCsv(),
            reader: DriftArticuloImportCatalogReader(h.db),
          );
          for (final entry in [
            ('', '', 'ok'),
            ('', 'conservar', 'ok'),
            ('13', '', 'ok'),
            ('13', 'establecer', 'ok'),
            ('', 'retirar', 'ok'),
            ('13', 'conservar', 'error'),
            ('13', 'retirar', 'error'),
            ('', 'establecer', 'error'),
            ('null', '', 'error'),
            ('0', 'establecer', 'error'),
            ('1.001', 'establecer', 'error'),
            ('21', 'establecer', 'error'),
            ('-1', 'establecer', 'error'),
            ('90071992547409.92', 'establecer', 'error'),
            ('', 'desconocida', 'error'),
          ]) {
            final row = [...source.last];
            row[12] = entry.$1;
            row[13] = entry.$2;
            final report = await preparation.preparar(
              '${source.first.join(',')}\n${row.join(',')}\n',
            );
            expect(
              report.errores.isEmpty,
              entry.$3 == 'ok',
              reason: entry.toString(),
            );
            if (entry.$3 == 'ok' && entry.$1.isEmpty && entry.$2 != 'retirar') {
              expect(report.productosConCambios, isEmpty);
            }
            expect(await fotoRecepcion(h.db), before);
          }
        },
      );
      test(
        'capacidad se exige antes de escribir en server_sync, standalone no la consulta',
        () async {
          var compatible = false, calls = 0;
          final guarded = ProductoCommandService(
            requireOfferPricing: () async {
              calls++;
              if (!compatible) {
                throw StateError('offer_pricing_v2 no acreditado');
              }
            },
            eventStore: h.events,
            commandContext: h.tracking.context,
            categoriaProjectionStore: h.tracking.categories,
            syncedEventHistory: h.tracking.history,
            unidadInventarioRepository: UnidadInventarioRepositoryImpl(
              unitDao: h.db.unitDao,
            ),
            inventoryProjectionStore: h.tracking.inventory,
            productoProjectionStore: h.tracking.products,
            proveedorProjectionStore: h.tracking.suppliers,
          );
          const command = CrearArticuloCommand.conVariantes(
            nombre: 'Capacidad',
            variantes: [
              CrearArticuloVarianteCommand(
                nombre: null,
                precioVenta: '20',
                costoEstandar: '3',
                offerPrice: CambioExplicito.establecer('15'),
              ),
            ],
          );
          if (mode == AppMode.serverSync) {
            final before = await fotoRecepcion(h.db);
            await expectLater(guarded.crearArticulo(command), throwsStateError);
            expect(await fotoRecepcion(h.db), before);
            compatible = true;
          }
          await guarded.crearArticulo(command);
          expect(calls, mode == AppMode.standalone ? 0 : 2);
        },
      );
      test(
        'CSV parcial directo valida conservación de oferta y base antigua',
        () async {
          final id = await create();
          final s = await h.tracking.products.snapshot(id);
          final base = (await h.tracking.products.findProductById(
            id,
          ))!.lastEventId!;
          ActualizarArticuloCsvCommand command(int normal) =>
              ActualizarArticuloCsvCommand(
                productId: id,
                baseEventId: base,
                nombre: s.nombre,
                categoriaId: null,
                variantes: [
                  ActualizarArticuloVarianteCsvCommand(
                    variantId: s.variantes.single.id,
                    nombre: null,
                    precioVentaMinor: normal,
                    precioCosteMinor: 300,
                    codigoBarras: null,
                  ),
                ],
              );
          await expectLater(
            h.commands.actualizarArticuloDesdeCsv(command(1400)),
            throwsFormatException,
          );
          expect(
            await h.commands.actualizarArticuloDesdeCsv(command(2100)),
            isTrue,
          );
          expect(await offer(id), 1500);
          await expectLater(
            h.commands.actualizarArticuloDesdeCsv(command(2200)),
            throwsStateError,
          );
        },
      );
    });
  }
}
