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
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';

// Manual benchmark: flutter test tool/benchmarks/articulo_import_baseline.dart --reporter expanded
// Fresh SQLite memory database per run, one discarded warm-up per fixture.
void main() {
  test('baseline 500 altas aisladas', () async {
    final results = <Map<String, Object?>>[];
    for (final tracking in [false, true]) {
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
        config = AppConfigController(AppConfig.initial);
        sync = DriftSyncPersistence(
          db: db,
          eventDao: EventDao(db),
          eventRefDao: EventRefDao(db),
          syncCheckpointDao: SyncCheckpointDao(db),
        );
        categorias = DriftCategoriaProjectionStore(
          categoriaDao: CategoriaDao(db),
        );
        productos = DriftProductoProjectionStore(productoDao: ProductoDao(db));
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
                ...inventoryEventHandlers(InventoryEventHandler(inventario)),
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
            variantInventoryTrackingStore: DriftVariantInventoryTrackingStore(
              inventoryDao: InventoryDao(db),
              productoDao: ProductoDao(db),
            ),
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
          // Initialization and seeds excluded. Catalog initially has zero products.
          await unidades.obtenerUnidadesActivas();
          final fixture =
              'categoria,nombre_articulo,tipo_venta,unidad_venta,nombre_variante,precio_venta,precio_coste,seguimiento_existencias,existencias,codigo_barras\n'
              '${List.generate(500, (i) => ',Artículo $i,fraccion,kg,,18.005,10,${tracking ? "si,1.250" : "no,0"},00123').join("\n")}\n';
          counts.reset();
          final timer = Stopwatch()..start();
          final catalogo = ArticuloImportCatalogo(
            unidades: await unidades.obtenerUnidadesActivas(),
            nombresArticulos: (await ProductoRepositoryImpl(
              productoDao: ProductoDao(db),
            ).watchArticulos().first).map((p) => p.nombre).toSet(),
          );
          final report = const ArticuloImportCsv().validar(
            fixture,
            catalogo: catalogo,
          );
          final validationUs = timer.elapsedMicroseconds;
          final validationQueries = counts.snapshot();
          expect(report.errores, isEmpty);
          counts.reset();
          timer.reset();
          final result = await servicio.importar(
            report.productos,
            onProgress: (_) {},
          );
          final saveUs = timer.elapsedMicroseconds;
          final saveQueries = counts.snapshot();
          expect(result.productosImportados, 500);
          expect(result.lotesFallidos, isEmpty);
          final events = await db.select(db.events).get();
          expect(events.length, tracking ? 1000 : 500);
          expect(await db.select(db.eventRefs).get(), isEmpty);
          if (run >= 0) {
            results.add({
              'tracking': tracking,
              'run': run + 1,
              'validation_us': validationUs,
              'save_us': saveUs,
              'validation_sql': validationQueries,
              'save_sql': saveQueries,
              'batches': store.batches.length,
              'events': events.length,
              'peak_rss_bytes_cumulative_process': ProcessInfo.maxRss,
            });
          }
        } finally {
          await db.close();
          await config.dispose();
        }
      }
    }
    final output = Platform.environment['CSV_BENCH_OUTPUT'];
    if (output != null) {
      await File(
        output,
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(results));
    }
    // ignore: avoid_print
    print('CSV_BASELINE ${jsonEncode(results)}');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _Queries extends QueryInterceptor {
  int selects = 0,
      inserts = 0,
      updates = 0,
      deletes = 0,
      customs = 0,
      transactions = 0;
  void reset() {
    selects = 0;
    inserts = 0;
    updates = 0;
    deletes = 0;
    customs = 0;
    transactions = 0;
  }

  Map<String, int> snapshot() => {
    'selects': selects,
    'inserts': inserts,
    'updates': updates,
    'deletes': deletes,
    'customs': customs,
    'transactions': transactions,
  };
  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions++;
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) {
    selects++;
    return super.runSelect(e, s, a);
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
}

class _RecordingStore
    implements
        LocalEventStore,
        LocalAtomicEventBatchStore,
        LocalTransactionalEventStore {
  _RecordingStore(this.delegate);
  final DriftLocalEventStore delegate;
  final batches = <List<LocalEventAppend>>[];

  @override
  bool get isStandalone => delegate.isStandalone;

  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      delegate.runInTransaction(action);

  @override
  Future<void> appendAndApplyBatchAtomically(List<LocalEventAppend> entries) {
    batches.add(entries);
    return delegate.appendAndApplyBatchAtomically(entries);
  }

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) => throw StateError(
    'El importador debe usar una sola llamada atómica por lote.',
  );
}
