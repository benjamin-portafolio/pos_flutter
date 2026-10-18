import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_variante_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/producto_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/import/articulo_csv_contract.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/application/import/articulo_import_progreso.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/recurso_inventario_creado_payload.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';

import '../../support/product_supplier_harness.dart';

typedef _Target = ({String id, String variantId, String base, String name});
typedef _DbState = Map<String, List<Map<String, Object?>>>;

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late ProductSupplierHarness h;
      late _SqlAudit audit;
      late _TransactionProbe probe;
      late ArticuloImportBatchService batches;
      late ArticuloImportPreparationService preparation;
      String? failProductId;
      var failedAfterProjection = false;

      setUp(() {
        audit = _SqlAudit();
        h = ProductSupplierHarness(
          mode: mode,
          database: AppDatabase.forTesting(
            NativeDatabase.memory().interceptWith(audit),
          ),
        );
        failProductId = null;
        failedAfterProjection = false;
        final local = DriftLocalEventStore(
          db: h.db,
          eventDao: h.db.eventDao,
          eventRefDao: h.db.eventRefDao,
          appConfigController: h.tracking.config,
          eventProcessor: EventProcessor(
            handlers: {
              for (final type in [
                ProductoCreadoPayload.eventType,
                ProductoActualizadoPayload.eventType,
                RecursoInventarioCreadoPayload.eventType,
              ])
                type: (event) async {
                  await h.tracking.processor.apply(event);
                  if (event.eventType == ProductoActualizadoPayload.eventType &&
                      event.aggregateId == failProductId) {
                    final p = (await h.tracking.products.findProductById(
                      event.aggregateId,
                    ))!;
                    expect(p.lastEventId, event.eventId);
                    expect(
                      await h.db.select(h.db.inventoryItems).get(),
                      hasLength(25),
                    );
                    expect((await h.db.select(h.db.products).get()).length, 51);
                    expect(
                      (await h.db.select(h.db.productUpdateUndo).get())
                          .isNotEmpty,
                      mode == AppMode.serverSync,
                    );
                    failedAfterProjection = true;
                    throw StateError(
                      'fallo inyectado después de proyectar actualización',
                    );
                  }
                },
            },
          ),
        );
        probe = _TransactionProbe(local);
        batches = ArticuloImportBatchService(
          productoCommandService: _commands(h, probe),
          unidadInventarioRepository: UnidadInventarioRepositoryImpl(
            unitDao: h.db.unitDao,
          ),
        );
        preparation = ArticuloImportPreparationService(
          parser: const ArticuloImportCsv(),
          reader: DriftArticuloImportCatalogReader(h.db),
        );
      });
      tearDown(() => h.dispose());

      test('500 existentes, 20 cambios: solo 20 eventos y un lote', () async {
        final targets = await _seed(h, 500);
        final csv = _file([
          for (var i = 0; i < targets.length; i++)
            _row(targets[i], price: i < 20 ? '11' : '10'),
        ]);
        final report = await preparation.preparar(csv);
        expect(report.errores, isEmpty);
        expect(report.filasConCambios, 20);
        expect(report.filasSinCambios, 480);
        final omittedRows = (await h.db.select(h.db.productVariants).get())
            .where((v) => targets.skip(20).any((t) => t.variantId == v.id))
            .toList();
        audit.reset();
        audit.onSelect = (sql) {
          if (sql.contains('events') || sql.contains('product_variants')) {
            expect(
              probe.depth,
              greaterThan(0),
              reason: 'Preparación dentro de transacción: $sql',
            );
          }
        };
        final progress = <ArticuloImportProgreso>[];
        final result = await batches.importar(
          report.productos,
          actualizaciones: report.productosConCambios,
          omitidos: report.productosSinCambios,
          onProgress: (p) {
            expect(probe.depth, 0);
            progress.add(p);
          },
        );
        audit.onSelect = null;
        expect(result.productosTotales, 20);
        expect(result.productosCreados, 0);
        expect(result.productosActualizados, 20);
        expect(result.productosImportados, 20);
        expect(result.productosOmitidos, 480);
        expect(result.lotesProcesados, 1);
        expect(result.lotesFallidos, isEmpty);
        expect(progress.map((p) => p.productosImportados), [0, 20]);
        expect(probe.transactions, 1);
        expect(
          probe.entries.single.where(
            (e) => e.event.eventType == ProductoActualizadoPayload.eventType,
          ),
          hasLength(20),
        );
        final rows = await h.db.select(h.db.productVariants).get();
        for (final old in omittedRows) {
          expect(rows.singleWhere((v) => v.id == old.id), old);
        }
        expect(await h.db.select(h.db.events).get(), hasLength(520));
        expect(await h.db.select(h.db.inventoryMovements).get(), isEmpty);
        expect(
          await h.db.select(h.db.productUpdateUndo).get(),
          hasLength(mode == AppMode.standalone ? 0 : 20),
        );

        // Revisión fresca del mismo CSV: todos omitidos y cero escrituras.
        final before = await _state(h.db);
        final repeated = await preparation.preparar(csv);
        audit.reset();
        final again = await batches.importar(
          repeated.productos,
          actualizaciones: repeated.productosConCambios,
          omitidos: repeated.productosSinCambios,
          onProgress: (_) {},
        );
        expect(again.productosImportados, 0);
        expect(again.productosOmitidos, 500);
        expect(again.lotesTotales, 0);
        expect(audit.writes, 0);
        expect(audit.selects, isEmpty);
        expect(probe.transactions, 1);
        expect(await _state(h.db), before);
      });

      test(
        'lotes mixtos de 50 excluyen omitidos y preceden recursos',
        () async {
          final targets = await _seed(h, 28);
          final report = await preparation.preparar(
            _file([
              for (var i = 0; i < 27; i++) ...[
                _newRow('Nuevo $i'),
                _row(targets[i], price: '11'),
              ],
              _row(targets.last),
            ]),
          );
          expect(report.errores, isEmpty);
          final result = await batches.importar(
            report.productos,
            actualizaciones: report.productosConCambios,
            omitidos: report.productosSinCambios,
            onProgress: (_) => expect(probe.depth, 0),
          );
          expect(result.lotesFallidos, isEmpty);
          expect(result.productosTotales, 54);
          expect(result.productosCreados, 27);
          expect(result.productosActualizados, 27);
          expect(result.productosOmitidos, 1);
          expect(result.lotesProcesados, 2);
          expect(probe.transactions, 2);
          expect(
            probe.entries.map(
              (l) => l.where((e) => e.event.aggregateType == 'product').length,
            ),
            [50, 4],
          );
          for (final entries in probe.entries) {
            final resources = entries
                .takeWhile(
                  (e) =>
                      e.event.eventType ==
                      RecursoInventarioCreadoPayload.eventType,
                )
                .toList();
            expect(resources, isNotEmpty);
            expect(
              entries
                  .skip(resources.length)
                  .every((e) => e.event.aggregateType == 'product'),
              isTrue,
            );
            for (final entry in entries) {
              expect(entry.refs, isNotEmpty);
            }
          }
          expect(
            (await h.db.select(h.db.events).get()).every(
              (e) =>
                  e.deliveryStatus ==
                  (mode == AppMode.standalone ? 'not_required' : 'pending'),
            ),
            isTrue,
          );
          final persisted = await h.db.select(h.db.eventRefs).get();
          if (mode == AppMode.standalone) {
            expect(persisted, isEmpty);
          } else {
            for (final entry in probe.entries.expand((e) => e)) {
              expect(
                persisted
                    .where((r) => r.eventId == entry.event.eventId)
                    .map((r) => '${r.refType}:${r.refId}:${r.relationship}')
                    .toSet(),
                entry.refs
                    .map((r) => '${r.refType}:${r.refId}:${r.relationship}')
                    .toSet(),
              );
            }
          }
        },
      );

      test(
        'fallo después de proyectar revierte lote mixto y continúa',
        () async {
          final targets = await _seed(h, 26);
          final before = await _state(h.db);
          final report = await preparation.preparar(
            _file([
              for (var i = 0; i < 25; i++) ...[
                _newRow('Nuevo $i'),
                _row(targets[i], price: '11'),
              ],
              _row(targets.last, price: '12'),
            ]),
          );
          failProductId = targets[10].id;
          final progress = <ArticuloImportProgreso>[];
          _DbState? rolledBackState;
          probe.onRollback = () async {
            rolledBackState = await _state(h.db);
          };
          final result = await batches.importar(
            report.productos,
            actualizaciones: report.productosConCambios,
            onProgress: (p) {
              expect(probe.depth, 0);
              progress.add(p);
            },
          );
          expect(failedAfterProjection, isTrue);
          expect(rolledBackState, before);
          expect(progress.map((p) => p.productosFallidos), [0, 50, 50]);
          expect(result.productosImportados, 1);
          expect(result.productosCreados, 0);
          expect(result.productosActualizados, 1);
          expect(result.productosFallidos, 50);
          final failure = result.lotesFallidos.single;
          expect(failure.numero, 1);
          expect(failure.lineas, List.generate(50, (i) => i + 2));
          expect(
            failure.productIds.toSet(),
            targets.take(25).map((t) => t.id).toSet(),
          );
          expect(failure.motivo, contains('fallo inyectado'));
          expect(probe.transactions, 2);
          final events = await h.db.select(h.db.events).get();
          expect(events, hasLength(27));
          expect(await h.db.select(h.db.products).get(), hasLength(26));
          expect(await h.db.select(h.db.inventoryItems).get(), isEmpty);
          expect(await h.db.select(h.db.inventoryBalances).get(), isEmpty);
          expect(await h.db.select(h.db.inventoryMovements).get(), isEmpty);
          expect(
            await h.db.select(h.db.productUpdateUndo).get(),
            hasLength(mode == AppMode.standalone ? 0 : 1),
          );
          final rolledBackIds = probe.entries.first
              .map((e) => e.event.eventId)
              .toSet();
          expect(events.any((e) => rolledBackIds.contains(e.eventId)), isFalse);
          expect(
            (await h.db.select(h.db.eventRefs).get()).any(
              (e) => rolledBackIds.contains(e.eventId),
            ),
            isFalse,
          );
        },
      );

      test(
        'base confirmada obsoleta falla antes de cualquier aplicación',
        () async {
          final target = (await _seed(h, 1)).single;
          final report = await preparation.preparar(
            _file([_newRow('Alta'), _row(target, price: '11')]),
          );
          await h.commands.actualizarArticuloDesdeCsv(
            _update(target, price: 1200),
          );
          final before = await _state(h.db);
          final result = await batches.importar(
            report.productos,
            actualizaciones: report.productosConCambios,
            onProgress: (_) => expect(probe.depth, 0),
          );
          expect(result.productosFallidos, 2);
          expect(result.lotesFallidos.single.motivo, contains('cambió'));
          expect(probe.entries, isEmpty);
          expect(await _state(h.db), before);
        },
      );

      test(
        'comparación final sin diferencias no escribe ni crea undo',
        () async {
          final target = (await _seed(h, 1)).single;
          final report = await preparation.preparar(_file([_row(target)]));
          final before = await _state(h.db);
          audit.reset();
          final result = await batches.importar(
            [],
            actualizaciones: report.productosSinCambios,
            onProgress: (_) => expect(probe.depth, 0),
          );
          expect(result.productosImportados, 0);
          expect(result.productosOmitidos, 1);
          expect(audit.writes, 0);
          expect(probe.entries, isEmpty);
          expect(await _state(h.db), before);
        },
      );

      test(
        'rechaza store sin transacción exterior, exceso y duplicados',
        () async {
          final target = (await _seed(h, 1)).single;
          final before = await _state(h.db);
          final commands = _commands(h, _AtomicOnly(h.local));
          await expectLater(
            commands.importarArticulosLote(
              altas: const [
                CrearArticuloCommand(nombre: 'Nuevo', precioVenta: '10'),
              ],
              actualizaciones: [_update(target)],
            ),
            throwsStateError,
          );
          await expectLater(
            h.commands.importarArticulosLote(
              altas: List.generate(
                51,
                (i) =>
                    CrearArticuloCommand(nombre: 'Nuevo $i', precioVenta: '10'),
              ),
              actualizaciones: [],
            ),
            throwsFormatException,
          );
          await expectLater(
            h.commands.importarArticulosLote(
              altas: [],
              actualizaciones: [_update(target), _update(target)],
            ),
            throwsFormatException,
          );
          expect(await _state(h.db), before);
        },
      );

      if (mode == AppMode.standalone) {
        test(
          'runtime e importación mixta no resuelven servicios remotos',
          () async {
            var remoteCalls = 0;
            getIt.registerLazySingleton<SyncAvailabilityMonitor>(() {
              remoteCalls++;
              throw StateError('No iniciar actividad remota');
            });
            addTearDown(() => getIt.unregister<SyncAvailabilityMonitor>());
            final config = AppConfig.initial.copyWith(
              setupCompleted: true,
              backupProvider: BackupProvider.none,
            );
            await startConfiguredRuntimeServices(config);
            final target = (await _seed(h, 1)).single;
            final report = await preparation.preparar(
              _file([_row(target, price: '11'), _newRow('Nuevo')]),
            );
            final result = await batches.importar(
              report.productos,
              actualizaciones: report.productosConCambios,
              onProgress: (_) {},
            );
            await stopConfiguredRuntimeServices(config);
            expect(result.productosImportados, 2);
            expect(remoteCalls, 0);
            expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
            expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
          },
        );
      }
    });
  }
}

ProductoCommandService _commands(
  ProductSupplierHarness h,
  LocalEventStore store,
) => ProductoCommandService(
  eventStore: store,
  commandContext: h.tracking.context,
  categoriaProjectionStore: h.tracking.categories,
  syncedEventHistory: h.tracking.history,
  unidadInventarioRepository: UnidadInventarioRepositoryImpl(
    unitDao: h.db.unitDao,
  ),
  inventoryProjectionStore: h.tracking.inventory,
  productoProjectionStore: h.tracking.products,
  proveedorProjectionStore: h.tracking.suppliers,
  variantInventoryMemoryStore: h.tracking.memory,
  variantInventoryTrackingStore: h.tracking.tracking,
);

Future<List<_Target>> _seed(ProductSupplierHarness h, int count) async {
  await h.commands.crearArticulosLote([
    for (var i = 0; i < count; i++)
      CrearArticuloCommand(nombre: 'Existente $i', precioVenta: '10'),
  ]);
  return [
    for (final e in h.appends.where(
      (e) => e.event.eventType == ProductoCreadoPayload.eventType,
    ))
      (
        id: e.event.aggregateId,
        variantId: ProductoCreadoPayload.fromJson(
          e.event.payload,
        ).variantes.single.id,
        base: e.event.eventId,
        name: ProductoCreadoPayload.fromJson(e.event.payload).nombre,
      ),
  ];
}

String _file(List<String> rows) =>
    '${ArticuloCsvContract.columnas.join(',')}\n${rows.join('\n')}\n';
String _row(_Target t, {String price = '10'}) =>
    '${t.id},${t.variantId},,${t.name},unidad,,,$price,,no,9999,';
String _newRow(String name) => ',,,$name,unidad,,,10,,si,3,001';

ActualizarArticuloCsvCommand _update(_Target t, {int price = 1100}) =>
    ActualizarArticuloCsvCommand(
      productId: t.id,
      baseEventId: t.base,
      nombre: t.name,
      categoriaId: null,
      variantes: [
        ActualizarArticuloVarianteCsvCommand(
          variantId: t.variantId,
          nombre: null,
          precioVentaMinor: price,
          precioCosteMinor: null,
          codigoBarras: null,
        ),
      ],
    );

Future<Map<String, List<Map<String, Object?>>>> _state(AppDatabase db) async =>
    {
      for (final table in db.allTables)
        table.actualTableName:
            (await db
                    .customSelect(
                      'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                    )
                    .get())
                .map((r) => r.data)
                .toList(),
    };

class _AtomicOnly implements LocalEventStore, LocalAtomicEventBatchStore {
  _AtomicOnly(this.delegate);
  final DriftLocalEventStore delegate;
  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) => delegate.appendAndApply(event, refs: refs);
  @override
  Future<void> appendAndApplyBatchAtomically(List<LocalEventAppend> entries) =>
      delegate.appendAndApplyBatchAtomically(entries);
}

class _TransactionProbe extends _AtomicOnly
    implements LocalTransactionalEventStore {
  _TransactionProbe(super.delegate);
  int depth = 0;
  int transactions = 0;
  Future<void> Function()? onRollback;
  final entries = <List<LocalEventAppend>>[];
  @override
  bool get isStandalone => delegate.isStandalone;
  @override
  Future<T> runInTransaction<T>(Future<T> Function() action) async {
    transactions++;
    depth++;
    try {
      return await delegate.runInTransaction(action);
    } catch (_) {
      await onRollback?.call();
      rethrow;
    } finally {
      depth--;
    }
  }

  @override
  Future<void> appendAndApplyBatchAtomically(List<LocalEventAppend> entries) {
    expect(depth, 1);
    this.entries.add(entries);
    return super.appendAndApplyBatchAtomically(entries);
  }
}

class _SqlAudit extends QueryInterceptor {
  int writes = 0;
  final selects = <String>[];
  void Function(String)? onSelect;
  void reset() {
    writes = 0;
    selects.clear();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) {
    selects.add(s);
    onSelect?.call(s);
    return super.runSelect(e, s, a);
  }

  @override
  Future<int> runInsert(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return super.runInsert(e, s, a);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return super.runUpdate(e, s, a);
  }

  @override
  Future<int> runDelete(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return super.runDelete(e, s, a);
  }

  @override
  Future<void> runCustom(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return super.runCustom(e, s, a);
  }

  @override
  Future<void> runBatched(QueryExecutor e, BatchedStatements s) {
    writes++;
    return super.runBatched(e, s);
  }
}
