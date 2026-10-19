import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/operacion_edicion_masiva.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/borrador_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/controlador_edicion_masiva.dart';

import '../../test/support/product_supplier_harness.dart';
import '../../test/support/recepcion_masiva_fixture.dart';

// Manual desktop debug benchmark. Fresh FILE-backed SQLite for every run.
// One warm-up discarded + five comparable runs. Fixture/capture excluded.
void main() {
  test(
    'M48: carga, filtro, revisión, commit y diario en SQLite real',
    () async {
      final output = Platform.environment['BULK_BENCH_OUT'];
      if (output == null) {
        throw StateError(
          'Set BULK_BENCH_OUT to a synthetic evidence JSON path.',
        );
      }
      final dir = await Directory.systemTemp.createTemp('pos_bulk_bench_');
      final results = <Map<String, Object?>>[];
      final journal = <Map<String, Object?>>[];
      try {
        for (final mode in AppMode.values) {
          final template = File('${dir.path}/${mode.name}-template.sqlite');
          final seed = ProductSupplierHarness(
            database: AppDatabase.forTesting(NativeDatabase(template)),
            mode: mode,
          );
          // 100 real command-created products, five tracked variants each. All
          // capture targets have real creation events/history/bases and receipts.
          for (var p = 0; p < 100; p++) {
            await seed.commands.crearArticulo(
              CrearArticuloCommand.conVariantes(
                nombre: 'Artículo ${p.toString().padLeft(5, '0')}',
                variantes: [
                  for (var v = 0; v < 5; v++)
                    CrearArticuloVarianteCommand(
                      nombre: 'Variante $v',
                      precioVenta: '20',
                      costoEstandar: '10',
                      inventoryUnitId: InventoryUnitIds.piece,
                      initialStockQuantity: '5',
                    ),
                ],
              ),
            );
          }
          await seed.dispose();
          for (final total in [1000, 10000]) {
            final sized = await template.copy(
              '${dir.path}/${mode.name}-$total-template.sqlite',
            );
            final sizedDb = AppDatabase.forTesting(NativeDatabase(sized));
            // Additional complete list projections, not command targets. Their
            // history is deliberately absent; no claim about huge sync histories.
            await sizedDb.batch((b) {
              b.insertAll(sizedDb.products, [
                for (var p = 100; p < total ~/ 5; p++)
                  ProductsCompanion.insert(
                    id: 'extra-p-$p',
                    name: 'Artículo ${p.toString().padLeft(5, '0')}',
                  ),
              ]);
              b.insertAll(sizedDb.inventoryItems, [
                for (var i = 500; i < total; i++)
                  InventoryItemsCompanion.insert(
                    id: 'extra-r-$i',
                    defaultUnitId: InventoryUnitIds.piece,
                    name: 'Recurso $i',
                  ),
              ]);
              b.insertAll(sizedDb.inventoryBalances, [
                for (var i = 500; i < total; i++)
                  InventoryBalancesCompanion.insert(
                    inventoryItemId: 'extra-r-$i',
                    quantityOnHandAtomic: 5,
                    quantityAvailableAtomic: 5,
                    lastEventId: 'extra-e-$i',
                  ),
              ]);
              b.insertAll(sizedDb.productVariants, [
                for (var i = 500; i < total; i++)
                  ProductVariantsCompanion.insert(
                    id: 'extra-v-$i',
                    productId: 'extra-p-${i ~/ 5}',
                    name: Value('Variante ${i % 5}'),
                    nameKey: Value('variante ${i % 5}'),
                    salePriceMinor: 2000,
                    standardCostMinor: const Value(1000),
                    inventoryItemId: Value('extra-r-$i'),
                    sortOrder: i % 5,
                  ),
              ]);
            });
            await sizedDb.close();
            for (final count in [20, 100, 500]) {
              for (var run = -1; run < 5; run++) {
                final file = await sized.copy('${dir.path}/run.sqlite');
                final queries = _Queries();
                final h = ProductSupplierHarness(
                  database: AppDatabase.forTesting(
                    NativeDatabase(file).interceptWith(queries),
                  ),
                  mode: mode,
                );
                final catalog = DriftCatalogoEdicionMasiva(h.db);
                final command = coordinadorRecepcion(h);
                // Open schema before timers, exactly as after application startup.
                await h.db.customSelect('SELECT 1').get();
                Future<Map<String, Object?>> phase(
                  Future<void> Function() action,
                ) async {
                  queries.reset();
                  final watch = Stopwatch()..start();
                  await action();
                  watch.stop();
                  return {
                    'ms': watch.elapsedMicroseconds / 1000,
                    ...queries.json,
                  };
                }

                final load = await phase(() async {
                  expect(await catalog.buscar(), hasLength(100));
                });
                final filter = await phase(() async {
                  expect(
                    await catalog.buscar(busqueda: 'Artículo 000'),
                    hasLength(100),
                  );
                });
                expect(load['history_rows'], 0);
                expect(filter['history_rows'], 0);
                final targets = [
                  for (var offset = 0; offset < count; offset += 100)
                    ...await catalog.buscar(
                      limite: count - offset < 100 ? count - offset : 100,
                      desplazamiento: offset,
                    ),
                ];
                final draft = BorradorEdicionMasiva(
                  catalogo: catalog,
                  ahora: () => DateTime.utc(2026, 10, 18),
                );
                for (var i = 0; i < targets.length; i++) {
                  if ((i ~/ 5) % 5 == 0) {
                    await draft.editarVenta(targets[i].clave, '20.00');
                  } else {
                    await draft.editarCosto(targets[i].clave, '12');
                    if (i.isEven) {
                      await draft.editarCantidad(targets[i].clave, '2');
                    }
                  }
                }
                final review = await phase(() async {
                  final r = await draft.prepararRevision();
                  expect(r.tieneErrores, isFalse);
                  expect(r.filas, hasLength(count));
                });
                final revision = await draft.prepararRevision();
                final beforeEvents =
                    (await h.db.select(h.db.events).get()).length;
                final save = await phase(() async {
                  final ops = await command.confirmar(
                    batchId: const Uuid().v4(),
                    cambios: revision.cambios,
                  );
                  for (final op in ops) {
                    await command.ejecutar(op);
                  }
                });
                final events =
                    (await h.db.select(h.db.events).get()).length -
                    beforeEvents;
                final records = await command.registros();
                final receipts = records
                    .expand((r) => r.resultado!.entradas)
                    .length;
                final journalBytes =
                    (await h.db
                            .customSelect(
                              'SELECT coalesce(sum(length(intent_json) + length(coalesce(result_json, \'\'))), 0) n FROM bulk_edit_operations',
                            )
                            .getSingle())
                        .read<int>('n');
                final integrity = await h.db
                    .customSelect('PRAGMA integrity_check')
                    .getSingle();
                expect(integrity.data.values.single, 'ok');
                expect(
                  await h.db.customSelect('PRAGMA foreign_key_check').get(),
                  isEmpty,
                );
                if (mode == AppMode.standalone) {
                  expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
                }
                if (run >= 0) {
                  results.add({
                    'mode': mode.storageValue,
                    'catalog_variants': total,
                    'capture_variants': count,
                    'run': run + 1,
                    'load': load,
                    'filter': filter,
                    'review': review,
                    'save': save,
                    'events': events,
                    'receipts': receipts,
                    'product_operations': records.length,
                    'journal_json_bytes': journalBytes,
                  });
                }
                await h.dispose();
                await file.delete();
              }
            }
            await sized.delete();
          }
          // Cost of the current full-history recovery read. Valid canonical
          // confirmed records; no automatic replay, events or business writes.
          final jfile = await template.copy('${dir.path}/journal.sqlite');
          final q = _Queries();
          final h = ProductSupplierHarness(
            database: AppDatabase.forTesting(
              NativeDatabase(jfile).interceptWith(q),
            ),
            mode: mode,
          );
          final journalCatalog = DriftCatalogoEdicionMasiva(h.db);
          final journalTargets = [
            for (var offset = 0; offset < 500; offset += 100)
              ...await journalCatalog.buscar(desplazamiento: offset),
          ];
          Future<int> allocatedBytes() async {
            final count =
                (await h.db.customSelect('PRAGMA page_count').getSingle())
                        .data
                        .values
                        .single
                    as int;
            final size =
                (await h.db.customSelect('PRAGMA page_size').getSingle())
                        .data
                        .values
                        .single
                    as int;
            return count * size;
          }

          final initialBytes = await allocatedBytes();
          var previous = 0;
          for (final size in [100, 1000, 10000]) {
            await h.db.batch((b) {
              b.insertAll(h.db.bulkEditOperations, [
                for (var i = previous; i < size; i++)
                  _journalRow(
                    OperacionEdicionMasiva.confirmada(
                      batchId: const Uuid().v4(),
                      modo: mode,
                      cambios: [
                        cambioRecepcion(
                          journalTargets[i % journalTargets.length],
                          venta: 2500,
                          cantidad: 2,
                        ),
                      ],
                    ),
                  ),
              ]);
            });
            previous = size;
            final bytes =
                (await h.db
                        .customSelect(
                          'SELECT sum(length(intent_json)) n FROM bulk_edit_operations',
                        )
                        .getSingle())
                    .read<int>('n');
            final allocated = await allocatedBytes();
            for (var run = -1; run < 5; run++) {
              q.reset();
              final watch = Stopwatch()..start();
              final rows = await coordinadorRecepcion(h).registros();
              watch.stop();
              expect(rows, hasLength(size));
              if (run >= 0) {
                journal.add({
                  'mode': mode.storageValue,
                  'path': 'command',
                  'rows': size,
                  'run': run + 1,
                  'ms': watch.elapsedMicroseconds / 1000,
                  'intent_bytes': bytes,
                  'allocated_database_bytes': allocated,
                  'journal_allocated_delta_bytes': allocated - initialBytes,
                  ...q.json,
                });
              }
              final controller = ControladorEdicionMasiva(
                catalogo: DriftCatalogoEdicionMasiva(h.db),
                comando: coordinadorRecepcion(h),
              );
              try {
                q.reset();
                final elapsed = Stopwatch()..start();
                final rows = await controller.registros();
                elapsed.stop();
                expect(rows, hasLength(size));
                if (run >= 0) {
                  journal.add({
                    'mode': mode.storageValue,
                    'path': 'controller',
                    'rows': size,
                    'run': run + 1,
                    'ms': elapsed.elapsedMicroseconds / 1000,
                    'intent_bytes': bytes,
                    'allocated_database_bytes': allocated,
                    'journal_allocated_delta_bytes': allocated - initialBytes,
                    ...q.json,
                  });
                }
              } finally {
                controller.dispose();
              }
            }
          }
          await h.dispose();
        }
        await File(output).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'build': 'flutter test / debug / flutter_tester darwin-arm64',
            'sqlite': 'file-backed, fresh copy for every timed run',
            'runs': results,
            'journal': journal,
          }),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

BulkEditOperationsCompanion _journalRow(OperacionEdicionMasiva op) =>
    BulkEditOperationsCompanion.insert(
      operationId: op.operationId,
      batchId: op.batchId,
      productId: op.productId,
      mode: op.modo.storageValue,
      intentJson: op.intencionJson,
      localState: 'confirmada',
      confirmedAt: DateTime.utc(2026, 10, 18),
    );

class _Queries extends QueryInterceptor {
  int selects = 0,
      writes = 0,
      transactions = 0,
      outer = 0,
      historyRows = 0,
      rows = 0;
  void reset() {
    selects = writes = transactions = outer = historyRows = rows = 0;
  }

  Map<String, int> get json => {
    'selects': selects,
    'writes': writes,
    'transactions_including_savepoints': transactions,
    'outer_transactions': outer,
    'returned_rows': rows,
    'history_rows': historyRows,
  };
  @override
  TransactionExecutor beginTransaction(QueryExecutor parent) {
    transactions++;
    if (parent is! TransactionExecutor) outer++;
    return super.beginTransaction(parent);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) async {
    selects++;
    final r = await super.runSelect(e, s, a);
    rows += r.length;
    if (RegExp(r'\bevents\b').hasMatch(s)) historyRows += r.length;
    return r;
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
  Future<void> runBatched(QueryExecutor e, BatchedStatements b) {
    writes += b.arguments.length;
    return super.runBatched(e, b);
  }
}
