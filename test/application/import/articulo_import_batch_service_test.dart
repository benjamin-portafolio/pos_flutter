import 'package:pos_flutter/data/local/drift/drift_variant_inventory_tracking_store.dart';
import 'package:pos_flutter/data/local/drift/drift_variant_inventory_memory_store.dart';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/application/export/articulo_catalog_export_service.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/import/articulo_import_progreso.dart';
import 'package:pos_flutter/application/sync/categoria_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/categoria_movida_conflict_projection_restorer.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/inventory_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/producto_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/local/export/drift_articulo_catalog_export_service.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';

void main() {
  late AppDatabase db;
  late AppConfigController config;
  late DriftSyncPersistence sync;
  late DriftCategoriaProjectionStore categorias;
  late DriftProductoProjectionStore productos;
  late DriftInventoryProjectionStore inventario;
  late UnidadInventarioRepositoryImpl unidades;
  late _RecordingStore store;
  late ArticuloImportBatchService servicio;
  String? productoQueFalla;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    config = AppConfigController(AppConfig.initial);
    sync = DriftSyncPersistence(
      db: db,
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      syncCheckpointDao: SyncCheckpointDao(db),
    );
    categorias = DriftCategoriaProjectionStore(categoriaDao: CategoriaDao(db));
    productos = DriftProductoProjectionStore(productoDao: ProductoDao(db));
    inventario = DriftInventoryProjectionStore(
      inventoryDao: InventoryDao(db),
      unitDao: UnitDao(db),
    );
    unidades = UnidadInventarioRepositoryImpl(unitDao: UnitDao(db));
    productoQueFalla = null;
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
            ProductoCreadoPayload.eventType: (event) async {
              await handler.applyProductoCreado(event);
              if (ProductoCreadoPayload.fromJson(event.payload).nombre ==
                  productoQueFalla) {
                // Falla después de proyectar: ya se escribieron recursos, saldos,
                // movimientos y varios productos del lote dentro de la transacción.
                throw StateError('fallo inyectado en el handler');
              }
            },
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
  });

  tearDown(() async {
    await db.close();
    await config.dispose();
  });

  Future<ArticuloImportReporte> validar(
    String contenido, {
    Set<String> nombres = const {},
  }) async => const ArticuloImportCsv().validar(
    contenido,
    catalogo: ArticuloImportCatalogo(
      unidades: await unidades.obtenerUnidadesActivas(),
      nombresArticulos: nombres,
    ),
  );

  for (final modo in AppMode.values) {
    test(
      '500 filas generan 1000 eventos en orden, con 10 transacciones: $modo',
      () async {
        config.update(AppConfig.initial.copyWith(mode: modo));
        final reporte = await validar(_csv(500));
        expect(reporte.errores, isEmpty);
        final avances = <ArticuloImportProgreso>[];
        final resultado = await servicio.importar(
          reporte.productos,
          onProgress: avances.add,
        );
        expect(
          resultado.lotesFallidos,
          isEmpty,
          reason: resultado.lotesFallidos.map((f) => f.motivo).join('\n'),
        );
        expect(resultado.productosImportados, 500);
        expect(resultado.productosFallidos, 0);
        expect(resultado.lotesProcesados, 10);
        expect(avances.map((p) => p.productosImportados), [
          0,
          50,
          100,
          150,
          200,
          250,
          300,
          350,
          400,
          450,
          500,
        ]);
        expect(store.batches, hasLength(10));
        expect(await db.select(db.products).get(), hasLength(500));
        expect(await db.select(db.productVariants).get(), hasLength(500));
        expect(await db.select(db.inventoryItems).get(), hasLength(500));
        expect(await db.select(db.inventoryMovements).get(), hasLength(500));
        final balances = await db.select(db.inventoryBalances).get();
        expect(balances, hasLength(500));
        expect(
          balances.every((balance) => balance.quantityOnHandAtomic == 1250),
          isTrue,
        );
        final events = await (db.select(
          db.events,
        )..orderBy([(e) => OrderingTerm(expression: e.localSequence)])).get();
        expect(events, hasLength(1000));
        expect(
          events.every(
            (e) =>
                e.deliveryStatus ==
                (modo == AppMode.standalone ? 'not_required' : 'pending'),
          ),
          isTrue,
        );
        final refs = await db.select(db.eventRefs).get();
        expect(refs.isEmpty, modo == AppMode.standalone);
        for (var lote = 0; lote < 10; lote++) {
          final batch = events.sublist(lote * 100, (lote + 1) * 100);
          expect(
            batch
                .take(50)
                .every(
                  (e) =>
                      e.eventType == RecursoInventarioCreadoPayload.eventType,
                ),
            isTrue,
          );
          expect(
            batch
                .skip(50)
                .every((e) => e.eventType == ProductoCreadoPayload.eventType),
            isTrue,
          );
          for (var index = 0; index < 50; index++) {
            final resource = batch[index];
            final resourcePayload = RecursoInventarioCreadoPayload.fromJson(
              jsonDecode(resource.payload) as Map<String, Object?>,
            );
            expect(
              resourcePayload.initialMovement!.movementType,
              TipoMovimientoInventario.initialBalance,
            );
            expect(resourcePayload.initialMovement!.quantityDeltaAtomic, 1250);
            final product = ProductoCreadoPayload.fromJson(
              jsonDecode(batch[50 + index].payload) as Map<String, Object?>,
            );
            expect(
              product.dependenciasInventario.single.dependsOnEventId,
              resource.eventId,
            );
            expect(
              product.variantes.single.inventoryItemId,
              resource.aggregateId,
            );
          }
        }
      },
    );
  }

  test(
    'un lote fallido revierte todo y conserva los anteriores y posteriores',
    () async {
      config.update(AppConfig.initial.copyWith(mode: AppMode.serverSync));
      productoQueFalla = 'Artículo 60';
      final reporte = await validar(_csv(120));
      final resultado = await servicio.importar(
        reporte.productos,
        onProgress: (_) {},
      );
      expect(resultado.productosImportados, 70);
      expect(resultado.productosFallidos, 50);
      expect(resultado.lotesProcesados, 3);
      final fallo = resultado.lotesFallidos.single;
      expect(fallo.numero, 2);
      expect(fallo.lineas, List.generate(50, (i) => i + 52));
      expect(fallo.productos, contains('Artículo 60'));
      expect(fallo.motivo, contains('fallo inyectado'));
      final rows = await db.select(db.products).get();
      expect(rows, hasLength(70));
      expect(
        rows.map((p) => p.name),
        containsAll([
          'Artículo 0',
          'Artículo 49',
          'Artículo 100',
          'Artículo 119',
        ]),
      );
      expect(
        rows.any(
          (p) =>
              p.name == 'Artículo 50' ||
              p.name == 'Artículo 60' ||
              p.name == 'Artículo 99',
        ),
        isFalse,
      );
      expect(await db.select(db.events).get(), hasLength(140));
      expect(await db.select(db.inventoryItems).get(), hasLength(70));
      expect(await db.select(db.inventoryMovements).get(), hasLength(70));
      expect(await db.select(db.inventoryBalances).get(), hasLength(70));
      final failedEventIds = store.batches[1]
          .map((e) => e.event.eventId)
          .toSet();
      final refs = await db.select(db.eventRefs).get();
      expect(refs.any((ref) => failedEventIds.contains(ref.eventId)), isFalse);
    },
  );

  test('las variantes de un producto no se parten entre lotes', () async {
    final texto =
        '${_csv(49)},Con variantes,unidad,,Chica,18.005,,si,0,00123\n'
        ',Con variantes,unidad,,Grande,20,0,si,2,\n';
    final reporte = await validar(texto);
    expect(reporte.errores, isEmpty);
    await servicio.importar(reporte.productos, onProgress: (_) {});
    expect(store.batches, hasLength(1));
    expect(store.batches.single, hasLength(101)); // 51 recursos, 50 productos.
    final product = ProductoCreadoPayload.fromJson(
      store.batches.single.last.event.payload,
    );
    expect(product.variantes.map((v) => v.nombre), ['Chica', 'Grande']);
    expect(product.variantes.map((v) => v.precioVentaMenor), [1801, 2000]);
    expect(product.variantes.map((v) => v.costoEstandarMenor), [null, 0]);
    expect(product.variantes.first.codigoBarras, '00123');
    expect(product.variantes.map((v) => v.orden), [0, 1]);
  });

  test(
    'exportar y reimportar sin cambios no altera catálogo, saldos ni eventos',
    () async {
      final reporte = await validar(_csv(3));
      await servicio.importar(reporte.productos, onProgress: (_) {});
      final temp = await Directory.systemTemp.createTemp('fase4-roundtrip');
      try {
        final exportador = DriftArticuloCatalogExportService(
          productoDao: ProductoDao(db),
          configStore: _ConfigStore(),
          directorio: () async => temp,
        );
        final archivo = await exportador.exportarCatalogo(
          ArticuloExportFiltro.sinFiltros,
        );
        final contenido = await File(archivo.ruta).readAsString();
        final before = await db
            .customSelect('SELECT * FROM products ORDER BY id')
            .get();
        final balancesBefore = await db.select(db.inventoryBalances).get();
        final nombres = (await ProductoRepositoryImpl(
          productoDao: ProductoDao(db),
        ).watchArticulos().first).map((p) => p.nombre).toSet();
        final vuelta = await validar(contenido, nombres: nombres);
        expect(vuelta.productos, isEmpty);
        expect(vuelta.errores, hasLength(3));
        expect(
          vuelta.errores.every((e) => e.motivo.contains('Ya existe')),
          isTrue,
        );
        await servicio.importar(vuelta.productos, onProgress: (_) {});
        final after = await db
            .customSelect('SELECT * FROM products ORDER BY id')
            .get();
        expect(after.map((r) => r.data), before.map((r) => r.data));
        expect(await db.select(db.inventoryBalances).get(), balancesBefore);
        expect(await db.select(db.events).get(), hasLength(6));
        expect(store.batches, hasLength(1));
        final otraExportacion = await exportador.exportarCatalogo(
          ArticuloExportFiltro.sinFiltros,
        );
        expect(await File(otraExportacion.ruta).readAsString(), contenido);
      } finally {
        await temp.delete(recursive: true);
      }
    },
  );

  test(
    'push entrega los 1000 eventos en POST de hasta 150 y respeta dependencias',
    () async {
      config.update(AppConfig.initial.copyWith(mode: AppMode.serverSync));
      final reporte = await validar(_csv(500));
      await servicio.importar(reporte.productos, onProgress: (_) {});
      final enviados = <String>{};
      final tamanos = <int>[];
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final events = (body['events'] as List).cast<Map<String, dynamic>>();
        tamanos.add(events.length);
        expect(events.length, lessThanOrEqualTo(150));
        final resultados = <Map<String, Object?>>[];
        for (final json in events) {
          if (json['event_type'] == ProductoCreadoPayload.eventType) {
            final payload = ProductoCreadoPayload.fromJson(
              (json['payload'] as Map).cast<String, Object?>(),
            );
            for (final dependency in payload.dependenciasInventario) {
              expect(enviados, contains(dependency.dependsOnEventId));
            }
          }
          expect(enviados.add(json['event_id'] as String), isTrue);
          resultados.add({
            'event_id': json['event_id'],
            'status': 'accepted',
            'server_sequence': enviados.length,
          });
        }
        return http.Response(jsonEncode({'events': resultados}), 200);
      });
      addTearDown(client.close);
      final push = SyncPushService(
        syncPersistence: sync,
        endpointConfig: SyncEndpointConfig(initialBaseUrl: 'http://localhost'),
        conflictProjectionCleaner: SyncConflictProjectionCleaner(
          espacioProjectionStore: DriftEspacioProjectionStore(
            espacioDao: EspacioDao(db),
          ),
          categoriaProjectionStore: categorias,
          productoProjectionStore: productos,
          inventoryProjectionStore: inventario,
          categoriaConflictProjectionRestorer:
              CategoriaConflictProjectionRestorer(categorias),
          categoriaMovidaConflictProjectionRestorer:
              CategoriaMovidaConflictProjectionRestorer(categorias),
        ),
        client: client,
      );
      var pending = 1000;
      for (var intento = 0; pending > 0 && intento < 20; intento++) {
        final result = await push.pushPendingEvents();
        expect(result.total, pending);
        expect(result.synced, inInclusiveRange(1, 150));
        expect(result.rejected, 0);
        expect(result.conflicts, 0);
        pending = result.pending;
      }
      expect(pending, 0);
      expect(enviados, hasLength(1000));
      expect(tamanos.length, greaterThan(1));
      expect(await sync.pendingEvents(), isEmpty);
    },
  );
}

String _csv(int filas) =>
    '${ArticuloCatalogCsv.columnas.join(ArticuloCatalogCsv.separador)}\n'
    '${List.generate(filas, (i) => ',Artículo $i,fraccion,kg,,18.005,10,si,1.250,00123').join('\n')}\n';

class _RecordingStore implements LocalEventStore, LocalAtomicEventBatchStore {
  _RecordingStore(this.delegate);
  final DriftLocalEventStore delegate;
  final batches = <List<LocalEventAppend>>[];

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

class _ConfigStore implements AppConfigStore {
  @override
  Future<AppConfig> readConfig() async => AppConfig.initial;
  @override
  Future<void> saveConfig(AppConfig config) async {}
}
