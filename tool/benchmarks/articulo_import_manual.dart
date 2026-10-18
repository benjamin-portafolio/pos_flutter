import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/export/drift_articulo_catalog_export_service.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/inventory_articles_tab.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/carga_masiva/bulk_import_screen.dart';

import '../../test/support/product_supplier_harness.dart';

// Isolated manual desktop entry point. Never resolves the installed database,
// saved credentials, runtime sync or backup services. Uses real production UI.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final temp = await getTemporaryDirectory();
  final directory = await Directory(
    '${temp.path}/csv-session4-isolated',
  ).create(recursive: true);
  final h = ProductSupplierHarness(
    mode: AppMode.standalone,
    database: AppDatabase.forTesting(
      NativeDatabase(File('${directory.path}/manual.sqlite')),
    ),
  );
  if ((await h.db.select(h.db.products).get()).isEmpty) {
    await h.commands.crearArticulo(
      CrearArticuloCommand.conVariantes(
        nombre: 'CSV Manual Café',
        variantes: [
          CrearArticuloVarianteCommand(
            nombre: 'Chica',
            precioVenta: '25',
            costoEstandar: '10',
            codigoBarras: '00123',
            inventoryUnitId: InventoryUnitIds.piece,
            initialStockQuantity: '12',
          ),
          CrearArticuloVarianteCommand(
            nombre: 'Grande',
            precioVenta: '35',
            costoEstandar: '15',
            codigoBarras: '00456',
          ),
        ],
      ),
    );
    await h.commands.crearArticulo(
      CrearArticuloCommand(nombre: 'CSV Manual Agua', precioVenta: '18'),
    );
  }
  // ignore: avoid_print
  print('CSV_MANUAL_DIRECTORY ${directory.path}');
  runApp(_CsvManualApp(h, directory));
}

class _CsvManualApp extends StatelessWidget {
  const _CsvManualApp(this.h, this.directory);
  final ProductSupplierHarness h;
  final Directory directory;
  @override
  Widget build(BuildContext context) {
    final exporter = DriftArticuloCatalogExportService(
      productoDao: h.db.productoDao,
      configStore: _ManualConfig(),
      directorio: () async => directory,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('CSV sesión 4 · base aislada · standalone'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BulkImportScreen(
                      exportService: exporter,
                      // The native picker was exercised separately. This
                      // explicit test-only seam continues the manual business
                      // flow when macOS entitlements block the plugin.
                      pickFile:
                          const bool.fromEnvironment('CSV_MANUAL_DIRECT_FILE')
                          ? () async => (
                              nombre: 'catalogo_2026-10-18.csv',
                              contenido: await File(
                                '${directory.path}/catalogo_2026-10-18.csv',
                              ).readAsString(),
                            )
                          : null,
                      preparationService: ArticuloImportPreparationService(
                        parser: const ArticuloImportCsv(),
                        reader: DriftArticuloImportCatalogReader(h.db),
                      ),
                      batchService: ArticuloImportBatchService(
                        productoCommandService: h.commands,
                        unidadInventarioRepository:
                            UnidadInventarioRepositoryImpl(
                              unitDao: h.db.unitDao,
                            ),
                      ),
                    ),
                  ),
                ),
                child: const Text('Carga masiva'),
              ),
            ],
          ),
          body: InventoryArticlesTab(
            productoRepository: h.repository,
            categoriaRepository: CategoriaRepositoryImpl(
              categoriaDao: h.db.categoriaDao,
            ),
            busqueda: '',
            onClearSearch: () {},
            onAddArticle: () {},
            exportService: exporter,
          ),
        ),
      ),
    );
  }
}

class _ManualConfig implements AppConfigStore {
  @override
  Future<AppConfig> readConfig() async => AppConfig.initial.copyWith(
    mode: AppMode.standalone,
    setupCompleted: true,
    backupProvider: BackupProvider.none,
  );
  @override
  Future<void> saveConfig(AppConfig config) =>
      throw UnsupportedError('No se guarda configuración en este recorrido.');
}
