import 'package:pos_flutter/data/local/drift/drift_variant_inventory_tracking_store.dart';
import 'package:pos_flutter/data/local/drift/drift_variant_inventory_memory_store.dart';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';

import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/application/import/articulo_csv_contract.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';

// Run manually; outside test/ to keep performance measurements out of CI.
// Each scenario/mode has one discarded warm-up and five fresh SQLite databases.
void main() {
  test(
    'C39-C42 mediciones CSV aisladas',
    () async {
      final results = <Map<String, Object?>>[];
      final selectedMode = Platform.environment['CSV_BENCH_MODE'];
      final selectedScenario = Platform.environment['CSV_BENCH_SCENARIO'];
      for (final mode in AppMode.values) {
        if (selectedMode != null && selectedMode != mode.storageValue) continue;
        for (final scenario in [
          'new_untracked',
          'new_tracked',
          'unchanged',
          'changed_20',
          'changed_all',
          'mixed',
          'large_unchanged',
        ]) {
          if (selectedScenario != null && selectedScenario != scenario) {
            continue;
          }
          final tracking = scenario != 'new_untracked';
          final isNew = scenario.startsWith('new_');
          for (var run = -1; run < 5; run++) {
            final counts = _Queries();
            final db = AppDatabase.forTesting(
              NativeDatabase.memory().interceptWith(counts),
            );
            late AppConfigController config;
            late DriftSyncPersistence sync;
            late DriftCategoriaProjectionStore categorias;
            late DriftProductoProjectionStore productos;
            late DriftInventoryProjectionStore inventario;
            late UnidadInventarioRepositoryImpl unidades;
            late _RecordingStore store;
            late ArticuloImportBatchService servicio;
            config = AppConfigController(
              AppConfig.initial.copyWith(mode: mode),
            );
            sync = DriftSyncPersistence(
              db: db,
              eventDao: EventDao(db),
              eventRefDao: EventRefDao(db),
              syncCheckpointDao: SyncCheckpointDao(db),
            );
            categorias = DriftCategoriaProjectionStore(
              categoriaDao: CategoriaDao(db),
            );
            productos = DriftProductoProjectionStore(
              productoDao: ProductoDao(db),
            );
            inventario = DriftInventoryProjectionStore(
              inventoryDao: InventoryDao(db),
              unitDao: UnitDao(db),
            );
            unidades = UnidadInventarioRepositoryImpl(unitDao: UnitDao(db));
            final handler = ProductoEventHandler(
              productos,
              variantInventoryMemoryStore: DriftVariantInventoryMemoryStore(
                dao: VariantInventoryMemoryDao(db),
              ),
              inventoryProjectionStore: inventario,
            );
            store = _RecordingStore(
              DriftLocalEventStore(
                db: db,
                eventDao: EventDao(db),
                eventRefDao: EventRefDao(db),
                appConfigController: config,
                eventProcessor: EventProcessor(
                  handlers: {
                    ...inventoryEventHandlers(
                      InventoryEventHandler(inventario),
                    ),
                    ...productoEventHandlers(handler),
                  },
                ),
              ),
            );
            servicio = ArticuloImportBatchService(
              productoCommandService: ProductoCommandService(
                variantInventoryMemoryStore: DriftVariantInventoryMemoryStore(
                  dao: VariantInventoryMemoryDao(db),
                ),
                variantInventoryTrackingStore:
                    DriftVariantInventoryTrackingStore(
                      inventoryDao: InventoryDao(db),
                      productoDao: ProductoDao(db),
                    ),
                productoProjectionStore: productos,
                inventoryProjectionStore: inventario,
                eventStore: store,
                commandContext: const LocalCommandContext(
                  deviceId: 'test-device',
                  userId: 'test-user',
                ),
                categoriaProjectionStore: categorias,
                syncedEventHistory: sync,
                unidadInventarioRepository: unidades,
              ),
              unidadInventarioRepository: unidades,
            );

            try {
              // Schema, seeds, fixtures and verification are outside both timers.
              await unidades.obtenerUnidadesActivas();
              final preparation = ArticuloImportPreparationService(
                parser: const ArticuloImportCsv(),
                reader: DriftArticuloImportCatalogReader(db),
              );
              final original = _newFixture(tracking);
              var fixture = original;
              var initialEvents = 0;
              var initialRefs = 0;
              var initialUndo = 0;
              if (!isNew) {
                final seed = await preparation.preparar(original);
                final seeded = await servicio.importar(
                  seed.productos,
                  onProgress: (_) {},
                );
                expect(seeded.productosCreados, 500);
                expect(seeded.lotesFallidos, isEmpty);
                final products = await db.select(db.products).get();
                final variants = await db.select(db.productVariants).get();
                final byProduct = {for (final v in variants) v.productId: v};
                final byName = {for (final p in products) p.name: p};
                fixture =
                    '${ArticuloCsvContract.columnas.join(',')}\n${[for (var i = 0; i < 500; i++)
                      if (scenario == 'mixed' && i % 5 == 0) ',,,Nuevo $i,fraccion,kg,,18.005,10,si,1.250,00123' else '${byName['Artículo $i']!.id},${byProduct[byName['Artículo $i']!.id]!.id},,Artículo $i,fraccion,kg,,${scenario == 'changed_all' || scenario == 'changed_20' && i < 20 || scenario == 'mixed' && i % 5 <= 2 ? '20' : '18.01'},10,si,999,00123'].join('\n')}\n';
                if (scenario == 'large_unchanged') {
                  // Fully populated extra projections; irrelevant history is not
                  // required to classify the 500 real command-created targets.
                  await db.batch((b) {
                    b.insertAll(db.products, [
                      for (var i = 500; i < 10000; i++)
                        ProductsCompanion.insert(
                          id: 'extra-p-$i',
                          name: 'Extra $i',
                        ),
                    ]);
                    b.insertAll(db.productVariants, [
                      for (var i = 500; i < 10000; i++)
                        ProductVariantsCompanion.insert(
                          id: 'extra-v-$i',
                          productId: 'extra-p-$i',
                          salePriceMinor: 1801,
                          sortOrder: 0,
                        ),
                    ]);
                  });
                }
                initialEvents = (await db.select(db.events).get()).length;
                initialRefs = (await db.select(db.eventRefs).get()).length;
                initialUndo =
                    (await db.select(db.productUpdateUndo).get()).length;
              }
              counts.reset();
              store.reset();
              final timer = Stopwatch()..start();
              final report = await preparation.preparar(fixture);
              final validationUs = timer.elapsedMicroseconds;
              final validationQueries = counts.snapshot();
              expect(report.errores, isEmpty);
              counts.reset();
              timer.reset();
              final result = await servicio.importar(
                report.productos,
                actualizaciones: report.productosConCambios,
                omitidos: report.productosSinCambios,
                onProgress: (_) {},
              );
              final saveUs = timer.elapsedMicroseconds;
              timer.stop();
              final saveQueries = counts.snapshot();
              expect(result.lotesFallidos, isEmpty);
              final expectedNew = isNew
                  ? 500
                  : scenario == 'mixed'
                  ? 100
                  : 0;
              final expectedUpdates = switch (scenario) {
                'changed_20' => 20,
                'changed_all' => 500,
                'mixed' => 200,
                _ => 0,
              };
              final expectedOmitted = 500 - expectedNew - expectedUpdates;
              expect(result.productosCreados, expectedNew);
              expect(result.productosActualizados, expectedUpdates);
              expect(result.productosOmitidos, expectedOmitted);
              expect(report.filasValidas, 500);
              final expectedBatches =
                  (expectedNew + expectedUpdates + 49) ~/ 50;
              expect(store.outerTransactions, expectedBatches);
              expect(result.lotesProcesados, expectedBatches);
              if (scenario == 'mixed') {
                expect(
                  store.batches.every(
                    (batch) =>
                        batch.any(
                          (e) =>
                              e.event.eventType ==
                              ProductoCreadoPayload.eventType,
                        ) &&
                        batch.any(
                          (e) =>
                              e.event.eventType ==
                              ProductoActualizadoPayload.eventType,
                        ),
                  ),
                  isTrue,
                );
              }
              final events = await db.select(db.events).get();
              final eventCount = events.length - initialEvents;
              expect(
                eventCount,
                expectedNew * (tracking ? 2 : 1) + expectedUpdates,
              );
              final refs =
                  (await db.select(db.eventRefs).get()).length - initialRefs;
              final undo =
                  (await db.select(db.productUpdateUndo).get()).length -
                  initialUndo;
              expect(undo, mode == AppMode.serverSync ? expectedUpdates : 0);
              expect(
                events.every(
                  (e) =>
                      e.deliveryStatus ==
                      (mode == AppMode.standalone ? 'not_required' : 'pending'),
                ),
                isTrue,
              );
              if (mode == AppMode.standalone) expect(refs, 0);
              expect(validationQueries['inserts'], 0);
              expect(validationQueries['updates'], 0);
              expect(validationQueries['deletes'], 0);
              expect(validationQueries['batch_statements'], 0);
              expect(validationQueries['history_selects'], 0);
              if (expectedOmitted == 500) {
                expect(saveQueries['selects'], 0);
                expect(saveQueries['inserts'], 0);
                expect(saveQueries['updates'], 0);
                expect(saveQueries['deletes'], 0);
                expect(saveQueries['batch_statements'], 0);
                expect(store.batches, isEmpty);
              }
              if (run >= 0) {
                results.add({
                  'mode': mode.storageValue,
                  'scenario': scenario,
                  'tracking': tracking,
                  'run': run + 1,
                  'catalog_products': isNew
                      ? 0
                      : scenario == 'large_unchanged'
                      ? 10000
                      : 500,
                  'validation_us': validationUs,
                  'save_us': saveUs,
                  'validation_sql': validationQueries,
                  'save_sql': saveQueries,
                  'outer_transactions_save': store.outerTransactions,
                  'batches': store.batches.length,
                  'events': eventCount,
                  'event_refs': refs,
                  'undo': undo,
                  'created': expectedNew,
                  'updated': expectedUpdates,
                  'omitted': expectedOmitted,
                  'peak_rss_bytes_cumulative_process': ProcessInfo.maxRss,
                });
              }
            } finally {
              await db.close();
              await config.dispose();
            }
          }
          // ignore: avoid_print
          print('CSV_SCENARIO ${mode.storageValue} $scenario complete');
          final output = Platform.environment['CSV_BENCH_OUTPUT'];
          if (output != null) {
            await File(output).writeAsString(
              const JsonEncoder.withIndent('  ').convert(results),
            );
          }
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

String _newFixture(bool tracking) =>
    '${ArticuloCsvContract.columnasAnteriores.join(',')}\n'
    '${List.generate(500, (i) => ',Artículo $i,fraccion,kg,,18.005,10,${tracking ? "si,1.250" : "no,0"},00123').join("\n")}\n';

class _Queries extends QueryInterceptor {
  int selects = 0,
      inserts = 0,
      updates = 0,
      deletes = 0,
      customs = 0,
      transactions = 0,
      outerTransactions = 0,
      batchStatements = 0,
      historySelects = 0,
      historyRows = 0;
  void reset() {
    selects = inserts = updates = deletes = customs = transactions =
        outerTransactions = batchStatements = historySelects = historyRows = 0;
  }

  Map<String, int> snapshot() => {
    'selects': selects,
    'inserts': inserts,
    'updates': updates,
    'deletes': deletes,
    'customs': customs,
    'transactions': transactions,
    'outer_transactions': outerTransactions,
    'batch_statements': batchStatements,
    'history_selects': historySelects,
    'history_rows': historyRows,
  };
  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions++;
    if (parent is! TransactionExecutor) outerTransactions++;
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) async {
    selects++;
    final result = await super.runSelect(e, s, a);
    if (s.contains('"events"')) {
      historySelects++;
      historyRows += result.length;
    }
    return result;
  }

  @override
  Future<int> runInsert(QueryExecutor e, String s, List<Object?> a) {
    inserts++;
    return super.runInsert(e, s, a);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String s, List<Object?> a) {
    updates++;
    return super.runUpdate(e, s, a);
  }

  @override
  Future<int> runDelete(QueryExecutor e, String s, List<Object?> a) {
    deletes++;
    return super.runDelete(e, s, a);
  }

  @override
  Future<void> runCustom(QueryExecutor e, String s, List<Object?> a) {
    customs++;
    return super.runCustom(e, s, a);
  }

  @override
  Future<void> runBatched(QueryExecutor e, BatchedStatements statements) {
    batchStatements += statements.arguments.length;
    return super.runBatched(e, statements);
  }
}

class _RecordingStore
    implements
        LocalEventStore,
        LocalAtomicEventBatchStore,
        LocalTransactionalEventStore {
  _RecordingStore(this.delegate);
  final DriftLocalEventStore delegate;
  final batches = <List<LocalEventAppend>>[];
  int outerTransactions = 0;
  void reset() {
    batches.clear();
    outerTransactions = 0;
  }

  @override
  bool get isStandalone => delegate.isStandalone;
  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    outerTransactions++;
    return delegate.runInTransaction(action);
  }

  @override
  Future<void> appendAndApplyBatchAtomically(List<LocalEventAppend> entries) {
    batches.add(entries);
    return delegate.appendAndApplyBatchAtomically(entries);
  }

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) => throw StateError('La importación debe guardar por lotes.');
}
