import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/proveedores/crear_proveedor_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/import/articulo_csv_contract.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/csv_records_parser.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

import '../../support/product_supplier_harness.dart';

String _csv(List<List<String>> rows, {String separator = ','}) => rows
    .map(
      (r) => r
          .map(
            (c) => c.contains(RegExp('[,;"\r\n]'))
                ? '"${c.replaceAll('"', '""')}"'
                : c,
          )
          .join(separator),
    )
    .join('\n');

void main() {
  for (final mode in AppMode.values) {
    group('CSV simplificado ${mode.name}', () {
      late ProductSupplierHarness h;
      late ArticuloImportPreparationService preparation;
      late ArticuloImportBatchService batch;
      late String supplier;
      late String other;
      setUp(() async {
        h = ProductSupplierHarness(mode: mode);
        supplier = await h.supplier('Distribuidora, "Norte"');
        other = await h.supplier('Alternativo');
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
            nombre: 'Arroz',
            saleConfiguration: MeasuredSaleConfiguration(
              saleUnitId: InventoryUnitIds.gram,
              priceReferenceQuantityAtomic: 1,
            ),
            variantes: [
              CrearArticuloVarianteCommand.conProveedores(
                nombre: null,
                precioVenta: '10',
                costoEstandar: '5',
                offerPrice: const CambioExplicito.establecer('8'),
                inventoryUnitId: InventoryUnitIds.kilogram,
                initialStockQuantity: '2.5',
                minimumStock: const CambioExplicito.establecer('1'),
                currentSupplier: CambioExplicito.establecer(supplier),
                targetStock: const CambioExplicito.establecer('3.5'),
                proveedores: [
                  for (final id in [supplier, other])
                    ProveedorVariante(
                      proveedorId: id,
                      precioInformadoMenor: 0,
                      fechaInformadaMs: 100,
                    ),
                ],
              ),
            ],
          ),
        );
      });
      tearDown(() => h.dispose());

      Future<List<List<String>>> rows() async => const CsvRecordsParser().parse(
        ArticuloCatalogCsv.catalogo(
          await h.db.productoDao.watchProductosListado().first,
        ),
        separator: ',',
      );
      Future<ArticuloImportReporte> review(Map<String, String> changes) async {
        final r = await rows();
        for (final c in changes.entries) {
          r[1][r.first.indexOf(c.key)] = c.value;
        }
        return preparation.preparar(_csv(r));
      }

      Future<void> apply(ArticuloImportReporte report) async {
        expect(report.errores, isEmpty);
        final result = await batch.importar(
          report.productos,
          actualizaciones: report.productosConCambios,
          omitidos: report.productosSinCambios,
          onProgress: (_) {},
        );
        expect(result.productosFallidos, 0);
      }

      test(
        'encabezado, oferta, nombres escapados y objetivo en kg con venta en g',
        () async {
          final r = await rows();
          expect(r.first, ArticuloCsvContract.columnasSimplificadas);
          expect(r[1].sublist(7, 10), ['10.00', '8.00', '5.00']);
          expect(r[1].sublist(11, 13), ['2.5', '3.5']);
          expect(r[1][14], 'Distribuidora, "Norte"');
          final before = await h.db.select(h.db.events).get();
          final report = await preparation.preparar(_csv(r, separator: ';'));
          await apply(report);
          expect(report.productosConCambios, isEmpty);
          expect(await h.db.select(h.db.events).get(), before);
        },
      );

      test(
        'nombre resuelto y decimal convertido; conserva saldo, mínimo y cotizaciones',
        () async {
          final balances = await h.db.select(h.db.inventoryBalances).get();
          final relations = await h.db.select(h.db.variantSuppliers).get();
          await apply(
            await review({
              'proveedor_actual': ' alternativo ',
              'existencias_objetivo': '4.125',
              'precio_venta': '11',
              'precio_oferta': '9',
              'precio_coste': '6',
            }),
          );
          final v = (await h.db.select(h.db.productVariants).get()).single;
          expect(v.currentSupplierId, other);
          expect(v.targetStockAtomic, 4125);
          expect(v.salePriceMinor, 1100);
          expect(v.offerPriceMinor, 900);
          expect(v.standardCostMinor, 600);
          expect(v.minimumStockAtomic, 1000);
          expect(await h.db.select(h.db.inventoryBalances).get(), balances);
          expect(await h.db.select(h.db.variantSuppliers).get(), relations);
          expect((await review({})).productosConCambios, isEmpty);
          final events = await h.db.select(h.db.events).get();
          expect(
            events.every(
              (e) =>
                  e.deliveryStatus ==
                  (mode == AppMode.standalone ? 'not_required' : 'pending'),
            ),
            isTrue,
          );
          expect(
            (await h.db.select(h.db.eventRefs).get()).isEmpty,
            mode == AppMode.standalone,
          );
        },
      );

      test(
        'vacío conserva proveedor/objetivo; RETIRAR retira sin borrar relaciones',
        () async {
          await apply(
            await review({
              'proveedor_actual': '',
              'existencias_objetivo': '',
              'precio_venta': '12',
            }),
          );
          var v = (await h.db.select(h.db.productVariants).get()).single;
          expect(v.currentSupplierId, supplier);
          expect(v.targetStockAtomic, 3500);
          await apply(
            await review({
              'proveedor_actual': 'retirar',
              'existencias_objetivo': 'RETIRAR',
            }),
          );
          v = (await h.db.select(h.db.productVariants).get()).single;
          expect(v.currentSupplierId, isNull);
          expect(v.targetStockAtomic, isNull);
          expect(await h.db.select(h.db.variantSuppliers).get(), hasLength(2));
          await apply(
            await review({
              'existencias_objetivo': '0',
              'proveedor_actual': 'Alternativo',
            }),
          );
          v = (await h.db.select(h.db.productVariants).get()).single;
          expect(v.targetStockAtomic, 0);
          expect(v.currentSupplierId, other);
        },
      );

      test(
        'proveedor inexistente, no asociado y nombre ambiguo rechazan sin escribir',
        () async {
          await h.supplier('Sin relación');
          await h.supplierCommands.crearProveedor(
            const CrearProveedorCommand(nombre: 'Alternativo'),
          );
          final before = await h.db.select(h.db.events).get();
          for (final name in ['Desconocido', 'Sin relación', 'Alternativo']) {
            final report = await review({'proveedor_actual': name});
            expect(report.errores, isNotEmpty, reason: name);
            expect(report.productosConCambios, isEmpty);
          }
          // Homónimos del proveedor actual nunca lo sustituyen por otro ID.
          await h.supplierCommands.crearProveedor(
            const CrearProveedorCommand(nombre: 'Distribuidora, "Norte"'),
          );
          final unchanged = await review({});
          expect(unchanged.errores, isEmpty);
          expect(unchanged.productosConCambios, isEmpty);
          expect(
            (await h.db.select(h.db.events).get()).length,
            before.length + 1,
          );
        },
      );

      test(
        'cantidad inválida y cambios de seguimiento rechazan antes de guardar',
        () async {
          final before = await h.db.select(h.db.events).get();
          for (final qty in ['-1', 'NaN', '1.0001', '9007199254740992']) {
            final report = await review({'existencias_objetivo': qty});
            expect(
              report.errores.any((e) => e.columna == 'existencias_objetivo'),
              isTrue,
            );
            expect(report.productosConCambios, isEmpty);
          }
          expect(
            (await review({'seguimiento_existencias': 'no'})).errores,
            isNotEmpty,
          );
          expect(await h.db.select(h.db.events).get(), before);
        },
      );

      test(
        'unidad cambiada tras revisión impide aplicar el objetivo',
        () async {
          final report = await review({'existencias_objetivo': '4.5'});
          expect(report.errores, isEmpty);
          final item = (await h.db.select(h.db.inventoryItems).get()).single;
          await (h.db.update(
            h.db.inventoryItems,
          )..where((t) => t.id.equals(item.id))).write(
            const InventoryItemsCompanion(
              defaultUnitId: Value(InventoryUnitIds.gram),
            ),
          );
          final before = await h.db.select(h.db.events).get();
          final result = await batch.importar(
            [],
            actualizaciones: report.productosConCambios,
            onProgress: (_) {},
          );
          expect(result.productosFallidos, 1);
          expect(await h.db.select(h.db.events).get(), before);
          expect(
            (await h.db.select(h.db.productVariants).get())
                .single
                .targetStockAtomic,
            3500,
          );
        },
      );

      test(
        'plantilla válida permite altas y rechaza configuración sin variante existente',
        () async {
          final template = ArticuloCatalogCsv.plantilla();
          final report = await preparation.preparar(template);
          await apply(report);
          expect(report.productos, hasLength(4));
          expect(report.filasNuevas, 5);
          final r = const CsvRecordsParser().parse(template, separator: ',');
          r.removeRange(2, r.length);
          r[1][3] = 'Alta inválida';
          r[1][14] = 'Alternativo';
          r[1][12] = '5';
          final invalid = await preparation.preparar(_csv(r));
          expect(invalid.errores, isNotEmpty);
          expect(invalid.productos, isEmpty);
        },
      );

      test(
        'objetivo dormido sin unidad se conserva al editar datos comerciales',
        () async {
          final v = (await h.db.select(h.db.productVariants).get()).single;
          final state = await h.tracking.products.snapshot(v.productId);
          await h.commands.actualizarArticulo(
            productId: v.productId,
            baseEventId: (await h.tracking.products.findProductById(
              v.productId,
            ))!.lastEventId!,
            variantIds: [v.id],
            command: CrearArticuloCommand.conVariantes(
              nombre: state.nombre,
              saleConfiguration: state.saleConfiguration,
              variantes: const [
                CrearArticuloVarianteCommand(
                  nombre: null,
                  precioVenta: '10',
                  costoEstandar: '5',
                  offerPrice: CambioExplicito.establecer('8'),
                ),
              ],
            ),
          );
          final r = await rows();
          expect(r[1][12], '');
          await apply(await review({'precio_venta': '12'}));
          final dormant =
              (await h.db.select(h.db.productVariants).get()).single;
          expect(dormant.inventoryItemId, isNull);
          expect(dormant.targetStockAtomic, 3500);
          expect(dormant.currentSupplierId, supplier);
        },
      );

      test('eliminar_variante sigue disponible en el formato nuevo', () async {
        await h.commands.crearArticulo(
          const CrearArticuloCommand.conVariantes(
            nombre: 'Tallas',
            variantes: [
              CrearArticuloVarianteCommand(
                nombre: 'Chica',
                precioVenta: '10',
                costoEstandar: null,
              ),
              CrearArticuloVarianteCommand(
                nombre: 'Grande',
                precioVenta: '10',
                costoEstandar: null,
              ),
            ],
          ),
        );
        final r = await rows();
        final selected = r.skip(1).singleWhere((c) => c[6] == 'Chica');
        selected[15] = 'si';
        final report = await preparation.preparar(_csv([r.first, selected]));
        await apply(report);
        final v = await h.db.select(h.db.productVariants).get();
        expect(v.singleWhere((v) => v.name == 'Chica').active, isFalse);
        expect(v.singleWhere((v) => v.name == 'Grande').active, isTrue);
      });

      test(
        'rechaza columnas faltantes, repetidas o reordenadas sin interpretar datos',
        () async {
          final r = await rows();
          for (final header in [
            r.first.take(15).toList(),
            [...r.first, r.first.last],
            [r.first[1], r.first[0], ...r.first.skip(2)],
          ]) {
            final report = await preparation.preparar(_csv([header, r[1]]));
            expect(report.erroresEstructurales, isTrue);
            expect(report.productosConCambios, isEmpty);
          }
        },
      );

      test(
        'nombres reservados se exportan literales y no retiran la asignación',
        () async {
          await (h.db.update(h.db.suppliers)
                ..where((t) => t.id.equals(supplier)))
              .write(const SuppliersCompanion(name: Value('RETIRAR')));
          var r = await rows();
          expect(r[1][14], '=RETIRAR');
          expect(
            (await preparation.preparar(_csv(r))).productosConCambios,
            isEmpty,
          );
          await (h.db.update(h.db.suppliers)
                ..where((t) => t.id.equals(supplier)))
              .write(const SuppliersCompanion(name: Value('=Proveedor')));
          r = await rows();
          expect(r[1][14], '==Proveedor');
          final report = await preparation.preparar(_csv(r));
          expect(report.errores, isEmpty);
          expect(report.productosConCambios, isEmpty);
        },
      );
    });
  }
}
