import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_variante_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/export/articulo_catalog_export_service.dart';
import 'package:pos_flutter/application/import/articulo_csv_contract.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/application/import/articulo_import_actualizacion.dart';
import 'package:pos_flutter/application/import/articulo_import_progreso.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/export/drift_articulo_catalog_export_service.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/carga_masiva/bulk_import_screen.dart';

import '../../../../support/product_supplier_harness.dart';

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late _Fixture f;
      setUp(() async {
        f = _Fixture(mode);
        await f.seed();
      });

      void uiTest(String name, Future<void> Function(WidgetTester) body) {
        testWidgets(name, (tester) async {
          tester.view.physicalSize = const Size(1000, 1400);
          tester.view.devicePixelRatio = 1;
          try {
            await body(tester);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.runAsync(f.dispose);
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          }
        });
      }

      Future<void> open(WidgetTester tester, String csv) async {
        f.file = csv;
        await tester.pumpWidget(
          MaterialApp(
            home: BulkImportScreen(
              preparationService: f.preparation,
              batchService: f.batch,
              pickFile: () async => (nombre: 'catalogo.csv', contenido: f.file),
            ),
          ),
        );
        await pick(tester);
      }

      uiTest(
        'C29→C05→C37 exportar, editar, revisar, guardar y reimportar sin eventos',
        (tester) async {
          final exported = (await tester.runAsync(f.export))!;
          expect(
            exported,
            startsWith(ArticuloCsvContract.columnasConIdsAnteriores.join(',')),
          );
          final lines = exported.trim().split('\n');
          final edited = <String>[];
          for (final line in lines.skip(1)) {
            final fields = line.split(',');
            if (fields[0] == f.complexId) {
              if (fields[6] == 'Omitida') continue;
              fields[2] = ''; // Retira categoría.
              fields[3] = 'Producto editado';
              fields[7] = '31.25';
              fields[8] = ''; // Costo desconocido.
              fields[10] = '9999'; // Saldo exportado informativo.
              fields[11] = fields[6] == 'Directa' ? '' : '000123';
            }
            edited.add(fields.join(','));
          }
          final csv = '${lines.first}\n${edited.join('\n')}\n';
          final before = (await tester.runAsync(f.state))!;
          final original = (await tester.runAsync(
            () => f.h.tracking.products.snapshot(f.complexId),
          ))!;
          await open(tester, csv);
          expect(
            find.textContaining('Con cambios: 1 productos · 2 filas.'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Sin cambios: 1 productos · 1 filas.'),
            findsOneWidget,
          );
          expect(
            await tester.runAsync(f.state),
            before,
            reason: 'Revisar no escribe',
          );
          await tester.ensureVisible(
            find.byKey(ValueKey('bulk_import_diff_${f.complexId}')),
          );
          await tester.tap(
            find.byKey(ValueKey('bulk_import_diff_${f.complexId}')),
          );
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Actual: Preparados\nPropuesta: Sin categoría'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Actual: 24.56\nPropuesta: 31.25'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Actual: 3.14\nPropuesta: Desconocido'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Actual: 009\nPropuesta: Vacío'),
            findsOneWidget,
          );
          await confirmDialog(tester);
          await accept(tester);
          expect(find.text('Artículos creados: 0'), findsOneWidget);
          expect(find.text('Artículos actualizados: 1'), findsOneWidget);
          expect(find.text('Artículos omitidos: 1'), findsOneWidget);
          final after = (await tester.runAsync(f.state))!;
          expect(after['events']!.length, before['events']!.length + 1);
          final saved = (await tester.runAsync(
            () => f.h.tracking.products.snapshot(f.complexId),
          ))!;
          expect(saved.nombre, 'Producto editado');
          expect(
            saved.variantes.map((v) => v.id),
            original.variantes.map((v) => v.id),
          );
          expect(
            saved.variantes.last.toJson(),
            original.variantes.last.toJson(),
          );
          for (var i = 0; i < 2; i++) {
            expect(
              saved.variantes[i].componentesReceta.map((r) => r.toJson()),
              original.variantes[i].componentesReceta.map((r) => r.toJson()),
            );
            expect(
              saved.variantes[i].proveedores?.map((p) => p.toJson()),
              original.variantes[i].proveedores?.map((p) => p.toJson()),
            );
          }
          for (final table in before.keys.where(
            (t) => !{
              'products',
              'product_variants',
              'events',
              'event_refs',
              'product_update_undo',
            }.contains(t),
          )) {
            expect(after[table], before[table], reason: table);
          }
          expect(after['event_refs']!.isEmpty, mode == AppMode.standalone);
          final update = f.h.appends.last.event;
          expect(update.eventType, ProductoActualizadoPayload.eventType);
          final eventRow = after['events']!.singleWhere(
            (e) => e['event_id'] == update.eventId,
          );
          expect(
            eventRow['delivery_status'],
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          await pick(tester);
          expect(
            find.text('Todo está sin cambios. No hay productos que guardar.'),
            findsOneWidget,
          );
          await visible(tester, 'confirm_bulk_import_button');
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('confirm_bulk_import_button')),
                )
                .onPressed,
            isNull,
          );
          expect(await tester.runAsync(f.state), after);
        },
      );

      uiTest(
        'C26 solo válidos excluye toda actualización inválida y permite alta y otro cambio',
        (tester) async {
          final csv = f.csv([
            f.row(
              f.complexId,
              f.directId,
              'Completo',
              'Directa',
              '12',
              tracked: true,
            ),
            f.row(f.complexId, f.recipeId, 'Completo', 'Receta', 'inválido'),
            f.row(f.simpleId, f.simpleVariant, 'Simple', '', '15'),
            ',,,Nuevo,unidad,,,20,,no,0,',
          ]);
          final before = (await tester.runAsync(
            () => f.h.tracking.products.snapshot(f.complexId),
          ))!;
          await open(tester, csv);
          expect(
            find.textContaining('Nuevos: 1 productos · 1 filas.'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              'Con errores: 1 productos · 2 filas excluidas.',
            ),
            findsOneWidget,
          );
          await confirmDialog(tester);
          await accept(tester);
          expect(find.text('Artículos creados: 1'), findsOneWidget);
          expect(find.text('Artículos actualizados: 1'), findsOneWidget);
          final unchanged = (await tester.runAsync(
            () => f.h.tracking.products.snapshot(f.complexId),
          ))!;
          expect(unchanged.toJson(), before.toJson());
          final names = (await tester.runAsync(
            () => f.h.db.select(f.h.db.products).get(),
          ))!.map((p) => p.name);
          expect(names, contains('Nuevo'));
        },
      );

      uiTest('C30 revisar y cancelar el diálogo conserva todas las tablas', (
        tester,
      ) async {
        final before = await tester.runAsync(f.state);
        await open(tester, f.simpleCsv('15'));
        await confirmDialog(tester);
        expect(await tester.runAsync(f.state), before);
        await tester.tap(find.byKey(const Key('cancel_bulk_import_dialog')));
        await tester.pumpAndSettle();
        expect(await tester.runAsync(f.state), before);
        expect(find.byKey(const Key('bulk_import_progress')), findsNothing);
      });

      uiTest(
        'C31 relee antes del diálogo y confirma diferencias y base actualizadas',
        (tester) async {
          await open(tester, f.simpleCsv('15'));
          await tester.runAsync(() => f.changeSimple(1200));
          final base = (await tester.runAsync(
            () => f.h.tracking.products.findProductById(f.simpleId),
          ))!.lastEventId;
          await confirmDialog(tester);
          final dialog = find.byType(AlertDialog);
          final diff = find.descendant(
            of: dialog,
            matching: find.byKey(ValueKey('bulk_import_diff_${f.simpleId}')),
          );
          await tester.ensureVisible(diff);
          await tester.tap(diff);
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: dialog,
              matching: find.textContaining('Actual: 12.00\nPropuesta: 15.00'),
            ),
            findsOneWidget,
          );
          await accept(tester);
          final update = ProductoActualizadoPayload.fromJson(
            f.h.appends.last.event.payload,
          );
          expect(update.baseEventId, base);
          expect(update.after.variantes.single.precioVentaMenor, 1500);
        },
      );

      uiTest(
        'C31 archivo queda sin cambios al releer: no abre diálogo ni escribe',
        (tester) async {
          await open(tester, f.simpleCsv('15'));
          await tester.runAsync(() => f.changeSimple(1500));
          final before = await tester.runAsync(f.state);
          await visible(tester, 'confirm_bulk_import_button');
          await tester.tap(find.byKey(const Key('confirm_bulk_import_button')));
          await settle(tester);
          expect(find.byType(AlertDialog), findsNothing);
          expect(
            find.text('Todo está sin cambios. No hay productos que guardar.'),
            findsOneWidget,
          );
          expect(await tester.runAsync(f.state), before);
        },
      );

      uiTest(
        'C32 cambio posterior al diálogo rechaza la base y revierte lote mixto',
        (tester) async {
          await open(
            tester,
            f.csv([
              ',,,Nueva alta,unidad,,,20,,no,0,',
              f.row(f.simpleId, f.simpleVariant, 'Simple', '', '15'),
            ]),
          );
          await confirmDialog(tester);
          await tester.runAsync(() => f.changeSimple(1200));
          final before = await tester.runAsync(f.state);
          await accept(tester);
          expect(find.text('Artículos fallidos: 2'), findsOneWidget);
          expect(
            find.textContaining(
              'Lote 1: 2 artículos revertidos. Líneas: 2, 3.',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('IDs: ${f.simpleId}'), findsOneWidget);
          expect(await tester.runAsync(f.state), before);
        },
      );

      uiTest(
        'C37 doble confirmación y guardado pendiente ejecutan un solo lote',
        (tester) async {
          final gate = Completer<void>();
          final batch = _GatedBatch(f.batch, gate);
          f.file = f.simpleCsv('15');
          await tester.pumpWidget(
            MaterialApp(
              home: BulkImportScreen(
                preparationService: f.preparation,
                batchService: batch,
                pickFile: () async =>
                    (nombre: 'catalogo.csv', contenido: f.file),
              ),
            ),
          );
          await pick(tester);
          await confirmDialog(tester);
          final button = tester.widget<FilledButton>(
            find.byKey(const Key('accept_bulk_import_dialog')),
          );
          button.onPressed!();
          button.onPressed!(); // Misma callback antes del siguiente frame.
          await tester.pump(const Duration(milliseconds: 400));
          expect(batch.calls, 1);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('pick_bulk_import_file_button')),
                )
                .onPressed,
            isNull,
          );
          gate.complete();
          await settle(tester);
          expect(batch.calls, 1);
          expect(find.text('Artículos actualizados: 1'), findsOneWidget);
          await visible(tester, 'confirm_bulk_import_button');
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('confirm_bulk_import_button')),
                )
                .onPressed,
            isNull,
          );
        },
      );

      uiTest(
        'C01 CSV anterior crea; el mismo nombre existente sigue siendo error',
        (tester) async {
          final header = ArticuloCsvContract.columnasAnteriores.join(',');
          await open(
            tester,
            '$header\n,Anterior,unidad,,,20,,no,0,\n,Simple,unidad,,,99,,no,0,\n',
          );
          expect(
            find.textContaining('Ya existe un producto llamado "Simple".'),
            findsOneWidget,
          );
          await confirmDialog(tester);
          await accept(tester);
          expect(find.text('Artículos creados: 1'), findsOneWidget);
          expect(find.text('Artículos actualizados: 0'), findsOneWidget);
          final simple = (await tester.runAsync(
            () => f.h.tracking.products.snapshot(f.simpleId),
          ))!;
          expect(simple.variantes.single.precioVentaMenor, 1000);
        },
      );

      uiTest('C28 errores estructurales bloquean toda escritura', (
        tester,
      ) async {
        final before = await tester.runAsync(f.state);
        final columnas = ArticuloCsvContract.columnas;
        final headers = [
          columnas.take(11).join(','),
          [...columnas, 'desconocida'].join(','),
          [...columnas, 'product_id'].join(','),
          columnas.reversed.join(','),
        ];
        for (final contenido in [
          for (final header in headers) '$header\n',
          f.csv(
            List.filled(
              501,
              f.row(f.simpleId, f.simpleVariant, 'Simple', '', '15'),
            ),
          ),
        ]) {
          await open(tester, contenido);
          expect(find.byKey(const Key('bulk_import_blocked')), findsOneWidget);
          await visible(tester, 'confirm_bulk_import_button');
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('confirm_bulk_import_button')),
                )
                .onPressed,
            isNull,
          );
          expect(await tester.runAsync(f.state), before);
        }
      });

      uiTest(
        'error después de proyectar revierte lote y muestra causa y productos',
        (tester) async {
          await open(
            tester,
            f.csv([
              ',,,Nueva alta,unidad,,,20,,no,0,',
              f.row(f.simpleId, f.simpleVariant, 'Simple', '', '15'),
            ]),
          );
          await confirmDialog(tester);
          final before = await tester.runAsync(f.state);
          f.h.failAfterProductApply = true;
          await accept(tester);
          expect(find.text('Artículos creados: 0'), findsOneWidget);
          expect(find.text('Artículos actualizados: 0'), findsOneWidget);
          expect(find.text('Artículos fallidos: 2'), findsOneWidget);
          expect(find.text('Artículos: Nueva alta, Simple'), findsOneWidget);
          expect(
            find.textContaining(
              'fallo inyectado después de proyectar producto e hijos',
            ),
            findsOneWidget,
          );
          expect(await tester.runAsync(f.state), before);
        },
      );
    });
  }
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> visible(WidgetTester tester, String key) =>
    tester.scrollUntilVisible(find.byKey(Key(key)), 250);
Future<void> pick(WidgetTester tester) async {
  await visible(tester, 'pick_bulk_import_file_button');
  await tester.tap(find.byKey(const Key('pick_bulk_import_file_button')));
  await settle(tester);
}

Future<void> confirmDialog(WidgetTester tester) async {
  await visible(tester, 'confirm_bulk_import_button');
  await tester.tap(find.byKey(const Key('confirm_bulk_import_button')));
  await settle(tester);
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> accept(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('accept_bulk_import_dialog')));
  await settle(tester);
}

class _Fixture {
  _Fixture(AppMode mode) : h = ProductSupplierHarness(mode: mode);
  final ProductSupplierHarness h;
  late Directory directory;
  late String complexId, directId, recipeId, simpleId, simpleVariant;
  String file = '';
  late final preparation = ArticuloImportPreparationService(
    parser: const ArticuloImportCsv(),
    reader: DriftArticuloImportCatalogReader(h.db),
  );
  late final batch = ArticuloImportBatchService(
    productoCommandService: h.commands,
    unidadInventarioRepository: UnidadInventarioRepositoryImpl(
      unitDao: h.db.unitDao,
    ),
  );

  Future<void> seed() async {
    directory = await Directory.systemTemp.createTemp('csv-ui-real-');
    await h.db
        .into(h.db.categories)
        .insert(
          CategoriesCompanion.insert(
            id: 'category',
            name: 'Preparados',
            sortOrder: 0,
            lastServerSequence: const Value(5),
          ),
        );
    final supplier = await h.supplier('Proveedor');
    await h.tracking.inventoryCommands.crearRecurso(
      const CrearRecursoInventarioCommand(
        nombre: 'Ingrediente',
        defaultUnitId: InventoryUnitIds.piece,
        quantityDeltaAtomic: 50,
      ),
    );
    final ingredient = (await h.db.select(h.db.inventoryItems).get()).single.id;
    await h.commands.crearArticulo(
      CrearArticuloCommand.conVariantes(
        nombre: 'Completo',
        categoriaId: 'category',
        saleConfiguration: const UnitSaleConfiguration(),
        variantes: [
          CrearArticuloVarianteCommand.conProveedores(
            nombre: 'Directa',
            precioVenta: '24.56',
            costoEstandar: '3.14',
            codigoBarras: '009',
            inventoryUnitId: InventoryUnitIds.piece,
            initialStockQuantity: '4',
            proveedores: [
              ProveedorVariante(
                proveedorId: supplier,
                precioInformadoMenor: 1299,
                fechaInformadaMs: 1791331200000,
              ),
            ],
          ),
          CrearArticuloVarianteCommand.conProveedores(
            nombre: 'Receta',
            precioVenta: '19.25',
            costoEstandar: null,
            codigoBarras: '0088',
            recipeComponents: [
              CrearArticuloRecipeComponentCommand(
                inventoryItemId: ingredient,
                quantity: '2',
              ),
            ],
            proveedores: [],
          ),
          const CrearArticuloVarianteCommand(
            nombre: 'Omitida',
            precioVenta: '10',
            costoEstandar: null,
          ),
        ],
      ),
    );
    complexId = h.appends.last.event.aggregateId;
    final complex = await h.tracking.products.snapshot(complexId);
    directId = complex.variantes[0].id;
    recipeId = complex.variantes[1].id;
    await h.commands.crearArticulo(
      const CrearArticuloCommand(
        nombre: 'Simple',
        precioVenta: '10',
        saleConfiguration: UnitSaleConfiguration(),
      ),
    );
    simpleId = h.appends.last.event.aggregateId;
    simpleVariant = (await h.tracking.products.snapshot(
      simpleId,
    )).variantes.single.id;
  }

  String csv(List<String> rows) =>
      '${ArticuloCsvContract.columnasConIdsAnteriores.join(',')}\n${rows.join('\n')}\n';
  String row(
    String p,
    String v,
    String name,
    String variant,
    String price, {
    bool tracked = false,
  }) => '$p,$v,,$name,unidad,,$variant,$price,,${tracked ? 'si' : 'no'},,';
  String simpleCsv(String price) =>
      csv([row(simpleId, simpleVariant, 'Simple', '', price)]);
  Future<void> changeSimple(int price) async {
    final product = (await h.tracking.products.findProductById(simpleId))!;
    await h.commands.actualizarArticuloDesdeCsv(
      ActualizarArticuloCsvCommand(
        productId: simpleId,
        baseEventId: product.lastEventId!,
        nombre: 'Simple',
        categoriaId: null,
        variantes: [
          ActualizarArticuloVarianteCsvCommand(
            variantId: simpleVariant,
            nombre: null,
            precioCosteMinor: null,
            codigoBarras: null,
            precioVentaMinor: price,
          ),
        ],
      ),
    );
  }

  Future<String> export() async {
    final service = DriftArticuloCatalogExportService(
      productoDao: h.db.productoDao,
      configStore: _ConfigStore(),
      directorio: () async => directory,
    );
    final file = await service.exportarCatalogo(
      ArticuloExportFiltro.sinFiltros,
    );
    return File(file.ruta).readAsString();
  }

  Future<Map<String, List<Map<String, Object?>>>> state() async => {
    for (final table in h.db.allTables)
      table.actualTableName:
          (await h.db
                  .customSelect(
                    'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                  )
                  .get())
              .map((r) => r.data)
              .toList(),
  };
  Future<void> dispose() async {
    await h.dispose();
    await directory.delete(recursive: true);
  }
}

class _GatedBatch implements ArticuloImportBatchService {
  _GatedBatch(this.delegate, this.gate);
  final ArticuloImportBatchService delegate;
  final Completer<void> gate;
  int calls = 0;
  @override
  Future<ArticuloImportProgreso> importar(
    List<ArticuloImportProducto> productos, {
    List<ArticuloImportActualizacion> actualizaciones = const [],
    List<ArticuloImportActualizacion> omitidos = const [],
    required void Function(ArticuloImportProgreso) onProgress,
  }) async {
    calls++;
    await gate.future;
    return delegate.importar(
      productos,
      actualizaciones: actualizaciones,
      omitidos: omitidos,
      onProgress: onProgress,
    );
  }
}

class _ConfigStore implements AppConfigStore {
  @override
  Future<AppConfig> readConfig() async => AppConfig.initial;
  @override
  Future<void> saveConfig(AppConfig config) async {}
}
