import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_variante_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/csv_records_parser.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';

import '../../support/product_supplier_harness.dart';

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late ProductSupplierHarness h;
      late ArticuloImportPreparationService preparation;
      late ArticuloImportBatchService batch;
      setUp(() async {
        h = ProductSupplierHarness(mode: mode);
        preparation = ArticuloImportPreparationService(
          parser: const ArticuloImportCsv(),
          reader: DriftArticuloImportCatalogReader(h.db),
        );
        batch = ArticuloImportBatchService(
          productoCommandService: h.commands,
          unidadInventarioRepository: UnidadInventarioRepositoryImpl(
            unitDao: h.db.unitDao,
          ),
        );
        await h.commands.crearArticulo(
          CrearArticuloCommand.conVariantes(
            nombre: 'Camiseta',
            variantes: const [
              CrearArticuloVarianteCommand(
                nombre: 'Chica',
                precioVenta: '25',
                costoEstandar: null,
                offerPrice: CambioExplicito.establecer('20'),
              ),
              CrearArticuloVarianteCommand(
                nombre: 'Grande',
                precioVenta: '25',
                costoEstandar: null,
              ),
            ],
          ),
        );
      });
      tearDown(() => h.dispose());
      Future<String> exportar() async => ArticuloCatalogCsv.catalogo(
        await h.db.productoDao.watchProductosListado().first,
      );
      Future<ArticuloImportReporte> revisarEliminacion({
        bool vaciar = false,
      }) async {
        final rows = const CsvRecordsParser().parse(
          await exportar(),
          separator: ',',
        );
        rows[1][13] = ' SI ';
        if (vaciar) {
          rows[1][1] = '';
          for (var i = 2; i < 13; i++) {
            rows[1][i] = '';
          }
        }
        return preparation.preparar(rows.map((r) => r.join(',')).join('\n'));
      }

      test(
        'exportar/importar intacto no genera eventos; omitir filas conserva variantes',
        () async {
          final csv = await exportar();
          expect(csv, contains(',20.00,'));
          final report = await preparation.preparar(csv);
          expect(report.errores, isEmpty);
          expect(report.productosConCambios, isEmpty);
          expect(report.productosSinCambios, hasLength(1));
          final before = await h.db.select(h.db.events).get();
          final result = await batch.importar(
            report.productos,
            actualizaciones: report.productosConCambios,
            omitidos: report.productosSinCambios,
            onProgress: (_) {},
          );
          expect(result.productosImportados, 0);
          expect(await h.db.select(h.db.events).get(), before);
          final partial = await preparation.preparar(
            '${csv.split('\n').take(2).join('\n')}\n',
          );
          expect(partial.eliminaciones, isEmpty);
          expect(
            partial.productosSinCambios.single.actual.variantes,
            hasLength(2),
          );
        },
      );
      for (final vaciar in [false, true]) {
        test(
          'una fila elimina dos variantes por el evento existente; vaciar=$vaciar',
          () async {
            final report = await revisarEliminacion(vaciar: vaciar);
            expect(report.errores, isEmpty);
            expect(report.eliminaciones, hasLength(1));
            final id = report.eliminaciones.single.actual.id;
            final before = (await h.db.select(h.db.events).get()).length;
            final result = await batch.importar(
              [],
              eliminaciones: report.eliminaciones,
              onProgress: (_) {},
            );
            expect(result.productosEliminados, 1);
            expect(result.productosActualizados, 0);
            expect(result.lotesFallidos, isEmpty);
            expect(await h.db.select(h.db.events).get(), hasLength(before + 1));
            expect(
              (await h.tracking.products.findProductById(id))!.active,
              isFalse,
            );
            expect(
              (await h.db.select(h.db.productVariants).get()).every(
                (v) => !v.active,
              ),
              isTrue,
            );
            final append = h.appends.last;
            expect(
              ProductoActualizadoPayload.fromJson(
                append.event.payload,
              ).deleteProduct,
              isTrue,
            );
            expect(
              append.refs.where((r) => r.refType == 'product_variant'),
              hasLength(2),
            );
            final events = await h.db.select(h.db.events).get();
            expect(
              events.every(
                (e) =>
                    e.deliveryStatus ==
                    (mode == AppMode.standalone ? 'not_required' : 'pending'),
              ),
              isTrue,
            );
            final refs = await h.db.select(h.db.eventRefs).get();
            expect(refs.isEmpty, mode == AppMode.standalone);
          },
        );
      }
      test(
        'cambio posterior a revisión rechaza eliminación y revierte el lote',
        () async {
          final report = await revisarEliminacion();
          final p = report.eliminaciones.single.actual;
          await h.commands.actualizarArticuloDesdeCsv(
            ActualizarArticuloCsvCommand(
              productId: p.id,
              baseEventId: p.lastEventId!,
              nombre: 'Nombre posterior',
              categoriaId: null,
              variantes: [
                for (final v in p.variantes)
                  ActualizarArticuloVarianteCsvCommand(
                    variantId: v.id,
                    nombre: v.nombre,
                    precioVentaMinor: v.precioVentaMinor,
                    precioCosteMinor: v.precioCosteMinor,
                    codigoBarras: v.codigoBarras,
                  ),
              ],
            ),
          );
          final before = await h.db.select(h.db.events).get();
          final result = await batch.importar(
            [],
            eliminaciones: report.eliminaciones,
            onProgress: (_) {},
          );
          expect(result.productosEliminados, 0);
          expect(result.productosFallidos, 1);
          expect(result.lotesFallidos.single.motivo, contains('cambió'));
          expect(await h.db.select(h.db.events).get(), before);
          expect(
            (await h.tracking.products.findProductById(p.id))!.active,
            isTrue,
          );
        },
      );
      test(
        'producto desactivado después de revisión rechaza eliminación',
        () async {
          final report = await revisarEliminacion();
          final p = report.eliminaciones.single.actual;
          await h.commands.eliminarArticulo(
            productId: p.id,
            baseEventId: p.lastEventId!,
          );
          final before = await h.db.select(h.db.events).get();
          final result = await batch.importar(
            [],
            eliminaciones: report.eliminaciones,
            onProgress: (_) {},
          );
          expect(result.productosFallidos, 1);
          expect(await h.db.select(h.db.events).get(), before);
        },
      );
      test(
        'fallo en proyección revierte producto, variantes y evento',
        () async {
          final report = await revisarEliminacion();
          final before = await h.db.select(h.db.events).get();
          final variants = await h.db.select(h.db.productVariants).get();
          h.failAfterProductApply = true;
          final result = await batch.importar(
            [],
            eliminaciones: report.eliminaciones,
            onProgress: (_) {},
          );
          expect(result.productosFallidos, 1);
          expect(result.productosEliminados, 0);
          expect(await h.db.select(h.db.events).get(), before);
          expect(await h.db.select(h.db.productVariants).get(), variants);
        },
      );
      if (mode == AppMode.serverSync) {
        test(
          'rechaza historial standalone sin importación explícita',
          () async {
            final report = await revisarEliminacion();
            await h.db.customStatement(
              'UPDATE events SET delivery_status = ?',
              ['not_required'],
            );
            final before = await h.db.select(h.db.events).get();
            final result = await batch.importar(
              [],
              eliminaciones: report.eliminaciones,
              onProgress: (_) {},
            );
            expect(result.productosFallidos, 1);
            expect(
              result.lotesFallidos.single.motivo,
              contains('importación explícita'),
            );
            expect(await h.db.select(h.db.events).get(), before);
            expect(
              (await h.db.select(h.db.products).get()).single.active,
              isTrue,
            );
          },
        );
      }
      test(
        'actualización obsoleta revierte también la eliminación del lote mixto',
        () async {
          await h.commands.crearArticulo(
            const CrearArticuloCommand(nombre: 'Otro', precioVenta: '25'),
          );
          final rows = const CsvRecordsParser().parse(
            await exportar(),
            separator: ',',
          );
          for (final row in rows.skip(1)) {
            if (row[3] == 'Camiseta') row[13] = 'si';
            if (row[3] == 'Otro') row[7] = '26';
          }
          final report = await preparation.preparar(
            rows.map((r) => r.join(',')).join('\n'),
          );
          expect(report.errores, isEmpty);
          expect(report.eliminaciones, hasLength(1));
          final update = report.productosConCambios.single;
          await h.commands.eliminarArticulo(
            productId: update.productId,
            baseEventId: update.baseEventId!,
          );
          final before = await h.db.select(h.db.events).get();
          final variants = await h.db.select(h.db.productVariants).get();
          final result = await batch.importar(
            [],
            eliminaciones: report.eliminaciones,
            actualizaciones: report.productosConCambios,
            onProgress: (_) {},
          );
          expect(result.productosFallidos, 2);
          expect(result.productosEliminados, 0);
          expect(await h.db.select(h.db.events).get(), before);
          expect(await h.db.select(h.db.productVariants).get(), variants);
          expect(
            (await h.tracking.products.findProductById(
              report.eliminaciones.single.actual.id,
            ))!.active,
            isTrue,
          );
        },
      );
    });
  }
}
