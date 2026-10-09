import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:pos_flutter/application/backup/backup_service.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/proveedores/crear_proveedor_command.dart';
import 'package:pos_flutter/application/commands/proveedores/editar_proveedor_command.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/proveedor_repository_impl.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/proveedor_precio_input.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';

import '../../../support/product_supplier_harness.dart';
import '../../../support/quotation_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Directory documents;
  late HttpOverrides? previousNetwork;
  late _NoNetwork network;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pos_supplier_acceptance_');
    documents = await Directory('${temp.path}/source').create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => documents.path,
        );
    previousNetwork = HttpOverrides.current;
    network = _NoNetwork();
    HttpOverrides.global = network;
  });
  tearDown(() async {
    HttpOverrides.global = previousNetwork;
    expect(network.clients, 0);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temp.delete(recursive: true);
  });

  Future<Map<String, Object?>> contents(AppDatabase db) async => {
    for (final table in db.allTables)
      table.actualTableName:
          (await db
                  .customSelect(
                    'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                  )
                  .get())
              .map((row) => row.data)
              .toList(),
  };

  Future<void> checkIntegrity(AppDatabase db) async {
    expect(
      (await db.customSelect('PRAGMA integrity_check').get())
          .single
          .data
          .values
          .single,
      'ok',
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect(
      (await db.customSelect('PRAGMA foreign_keys').get())
          .single
          .data
          .values
          .single,
      1,
    );
    expect(db.schemaVersion, 8);
    expect(await db.select(db.eventRefs).get(), isEmpty);
    expect(await db.eventDao.obtenerEventosPendientes(), isEmpty);
    final events = await db.select(db.events).get();
    expect(events, isNotEmpty);
    expect(
      events.every(
        (e) =>
            e.applicationStatus == 'applied' &&
            e.deliveryStatus == 'not_required',
      ),
      isTrue,
    );
  }

  Future<void> export(String name, Map<String, Object?> result) async {
    final output = Platform.environment['POS_SUPPLIER_VERIFICATION_DIR'];
    if (output == null) return;
    await Directory(output).create(recursive: true);
    await File(
      '$output/$name.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  }

  CrearArticuloVarianteCommand variant(
    String name,
    List<ProveedorVariante> quotes, {
    String? unit,
    String? initialStock,
    List<CrearArticuloRecipeComponentCommand> recipe = const [],
  }) => CrearArticuloVarianteCommand.conProveedores(
    nombre: name,
    precioVenta: '25',
    costoEstandar: '10',
    proveedores: quotes,
    inventoryUnitId: unit,
    initialStockQuantity: initialStock,
    recipeComponents: recipe,
  );

  ProveedorVariante quote(String supplier, int price, int at) =>
      ProveedorVariante(
        proveedorId: supplier,
        precioInformadoMenor: price,
        fechaInformadaMs: at,
      );

  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
  }

  for (final populated in [true, false]) {
    testWidgets(
      'F5 respaldo real entre directorios y reinicios: catálogo ${populated ? 'con proveedores' : 'vacío'}, repositorios e interfaz',
      (tester) async {
        var h = ProductSupplierHarness(database: AppDatabase());
        DatabaseSnapshot? snapshot;
        late String productId;
        late Map<String, Object?> before;
        late Map<String, Object?> sourceAfterBackup;
        late Directory source;
        final quotes = <List<ProveedorVariante>>[[], [], []];
        try {
          await tester.runAsync(() async {
            source = documents;
            if (populated) {
              await h.supplierCommands.crearProveedor(
                const CrearProveedorCommand(
                  nombre: '  Distribuidora Norte  ',
                  telefono: '  00123  ',
                  notas: '  Entrega semanal  ',
                ),
              );
              final base = (await ProveedorRepositoryImpl(
                h.db.proveedorDao,
              ).watchProveedores().first).single;
              await h.supplierCommands.editarProveedor(
                EditarProveedorCommand(
                  base: base,
                  nombre: 'Distribuidora Norte',
                  telefono: '00123',
                  notas: 'Entrega martes',
                ),
              );
              final other = await h.supplier('Proveedor Sur');
              quotes[0] = [
                quote(base.id, 0, 1791331200123),
                quote(other, 1234, 1791417600456),
              ];
              quotes[1] = [quote(base.id, 2345, 1791504000789)];
            }
            await h.commands.crearArticulo(
              CrearArticuloCommand.conVariantes(
                nombre: 'Café respaldo',
                variantes: [
                  variant('Chica', quotes[0]),
                  variant('Grande', quotes[1]),
                  variant('Sin oferta', quotes[2]),
                ],
              ),
            );
            productId = h.appends.last.event.aggregateId;
            await h.db.customStatement(
              'CREATE TABLE supplier_acceptance_marker(value TEXT)',
            );
            before = await contents(h.db);
            for (var restart = 0; restart < 2; restart++) {
              await h.dispose();
              h = ProductSupplierHarness(database: AppDatabase());
              expect(await contents(h.db), before);
              await checkIntegrity(h.db);
              final detail = (await h.repository.obtenerDetalle(productId))!;
              for (var i = 0; i < 3; i++) {
                expect(
                  detail.variantes[i].proveedores,
                  ProveedorVariante.canonical(quotes[i]),
                );
              }
              expect(
                await h.db
                    .customSelect(
                      "SELECT name FROM sqlite_master WHERE name='supplier_acceptance_marker'",
                    )
                    .get(),
                hasLength(1),
              );
            }
            snapshot = await DriftDatabaseSnapshotService(
              db: h.db,
              stateReader: DriftDatabaseStateReader(db: h.db),
            ).createSnapshot();
            expect(snapshot!.schemaVersion, 8);
            expect(snapshot!.eventCount, populated ? 4 : 1);
            expect(snapshot!.lastLocalSequence, snapshot!.eventCount);
            expect(
              sha256.convert(await snapshot!.file.readAsBytes()).toString(),
              snapshot!.sha256,
            );
            // El origen sigue disponible; restaurar sólo reemplaza el destino aislado.
            await h.supplier('Cambio posterior al respaldo');
            sourceAfterBackup = await contents(h.db);
            await h.dispose();
            documents = await Directory('${temp.path}/restore').create();
            h = ProductSupplierHarness(database: AppDatabase());
            await h.supplier('Sólo en destino');
            await DriftDatabaseRestoreService(
              db: h.db,
            ).restoreSnapshot(snapshot!.file, sha256: snapshot!.sha256);
            await h.tracking.config.dispose();
            h = ProductSupplierHarness(database: AppDatabase());
            for (var restart = 0; restart < 2; restart++) {
              expect(await contents(h.db), before);
              await checkIntegrity(h.db);
              expect(await appDatabaseShouldPreserveRestoredDatabase(), isTrue);
              final suppliers = await ProveedorRepositoryImpl(
                h.db.proveedorDao,
              ).watchProveedores().first;
              expect(suppliers, hasLength(populated ? 2 : 0));
              if (populated) {
                final north = suppliers.singleWhere(
                  (s) => s.nombre == 'Distribuidora Norte',
                );
                expect(north.telefono, '00123');
                expect(north.notas, 'Entrega martes');
                expect(north.version, 2);
                expect(north.createdEventId, isNot(north.lastEventId));
              }
              final detail = (await h.repository.obtenerDetalle(productId))!;
              expect(detail.nombre, 'Café respaldo');
              for (var i = 0; i < 3; i++) {
                expect(
                  detail.variantes[i].proveedores,
                  ProveedorVariante.canonical(quotes[i]),
                );
                expect(detail.variantes[i].precioVentaMenor, 2500);
                expect(detail.variantes[i].costoEstandarMenor, 1000);
              }
              await h.dispose();
              h = ProductSupplierHarness(database: AppDatabase());
            }
            await checkIntegrity(h.db);
          });

          await tester.pumpWidget(
            MaterialApp(
              home: InventoryManagementScreen(
                categoriaRepository: CategoriaRepositoryImpl(
                  categoriaDao: h.db.categoriaDao,
                ),
                productoRepository: h.repository,
                productoCommandService: h.commands,
                proveedorRepository: ProveedorRepositoryImpl(h.db.proveedorDao),
                proveedorCommandService: h.supplierCommands,
                appConfigController: h.tracking.config,
                unidadInventarioRepository: UnidadInventarioRepositoryImpl(
                  unitDao: h.db.unitDao,
                ),
                recursoInventarioRepository: RecursoInventarioRepositoryImpl(
                  inventoryDao: h.db.inventoryDao,
                ),
              ),
            ),
          );
          await flush(tester);
          await click(tester, find.text('Café respaldo Chica'));
          for (var i = 0; i < 3; i++) {
            await click(tester, find.byKey(Key('article_variant_card_$i')));
            await click(
              tester,
              find.byKey(const Key('manage_variant_suppliers_button')),
            );
            await flush(tester);
            final selected = quotes[i].map((q) => q.proveedorId).toSet();
            expect(find.byType(TextField), findsNWidgets(selected.length));
            for (final q in quotes[i]) {
              expect(
                tester
                    .widget<TextField>(
                      find.byKey(Key('supplier_price_${q.proveedorId}')),
                    )
                    .controller!
                    .text,
                ProveedorPrecioInput.format(q.precioInformadoMenor),
              );
            }
            for (final checkbox in tester.widgetList<CheckboxListTile>(
              find.byType(CheckboxListTile),
            )) {
              expect(
                checkbox.value,
                selected.contains(
                  (checkbox.key as ValueKey<String>).value.replaceFirst(
                    'select_variant_supplier_',
                    '',
                  ),
                ),
              );
            }
            await click(
              tester,
              find.byKey(const Key('close_variant_suppliers_button')),
            );
            await click(
              tester,
              find.byKey(const Key('close_variant_editor_button')),
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await flush(tester);
          await tester.runAsync(() async {
            expect(
              await contents(h.db),
              before,
            ); // Consultar/cancelar no escribe.
            await export(populated ? 'restore-populated' : 'restore-empty', {
              'schema_version': 8,
              'snapshot_sha256': snapshot!.sha256,
              'snapshot_event_count': snapshot!.eventCount,
              'snapshot_last_local_sequence': snapshot!.lastLocalSequence,
              'normal_restarts': 2,
              'restored_restarts': 2,
              'repository_and_ui_verified': true,
              'integrity_check': 'ok',
              'foreign_key_check': [],
              'http_clients': network.clients,
              'contents': before,
            });
            await h.dispose();
            documents = source;
            h = ProductSupplierHarness(database: AppDatabase());
            expect(await contents(h.db), sourceAfterBackup);
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await flush(tester);
          await tester.runAsync(() async {
            await h.dispose();
            if (snapshot != null) {
              await snapshot!.file.parent.delete(recursive: true);
            }
          });
        }
      },
    );
  }

  for (final invalid in [
    'sha256',
    'not-sqlite',
    'other-schema',
    'older-version',
    'newer-version',
  ]) {
    test(
      'F5 respaldo $invalid rechazado conserva base abierta y reinicio',
      () async {
        var h = ProductSupplierHarness(database: AppDatabase());
        DatabaseSnapshot? snapshot;
        try {
          final supplier = await h.supplier('Conservar');
          await h.commands.crearArticulo(
            CrearArticuloCommand.conVariantes(
              nombre: 'Conservar artículo',
              variantes: [
                variant('Única', [quote(supplier, 1234, 1791331200123)]),
              ],
            ),
          );
          final before = await contents(h.db);
          snapshot = await DriftDatabaseSnapshotService(
            db: h.db,
            stateReader: DriftDatabaseStateReader(db: h.db),
          ).createSnapshot();
          var hash = 'incorrecto';
          if (invalid == 'not-sqlite') {
            await snapshot.file.writeAsString('Esto no es una base SQLite.');
            hash = sha256.convert(await snapshot.file.readAsBytes()).toString();
          } else if (invalid != 'sha256') {
            final raw = sqlite.sqlite3.open(snapshot.file.path);
            try {
              if (invalid == 'other-schema') {
                raw.execute(
                  'ALTER TABLE product_variants RENAME COLUMN barcode TO legacy_barcode',
                );
              } else {
                raw.execute(
                  'PRAGMA user_version = ${invalid == 'older-version' ? 7 : 9}',
                );
              }
            } finally {
              raw.close();
            }
            hash = sha256.convert(await snapshot.file.readAsBytes()).toString();
          }
          await expectLater(
            DriftDatabaseRestoreService(
              db: h.db,
            ).restoreSnapshot(snapshot.file, sha256: hash),
            throwsA(
              invalid == 'not-sqlite'
                  ? isA<sqlite.SqliteException>()
                  : isA<StateError>(),
            ),
          );
          expect(await contents(h.db), before);
          expect(await appDatabaseShouldPreserveRestoredDatabase(), isFalse);
          await checkIntegrity(h.db);
          await h.dispose();
          h = ProductSupplierHarness(database: AppDatabase());
          expect(await contents(h.db), before);
          await checkIntegrity(h.db);
          await export('rejected-$invalid', {
            'rejected_before_replacement': true,
            'current_database_and_restart_preserved': true,
            'contents': before,
          });
        } finally {
          await h.dispose();
          if (snapshot != null) {
            await snapshot.file.parent.delete(recursive: true);
          }
        }
      },
    );
  }

  test(
    'F5 precios conservan ventas/caja, cotizaciones y existencias no vacías',
    () async {
      final h = ProductSupplierHarness(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      final sales = QuotationHarness(database: h.db);
      try {
        final supplier = await h.supplier('Proveedor comercial');
        await h.tracking.inventoryCommands.crearRecurso(
          const CrearRecursoInventarioCommand(
            nombre: 'Ingrediente',
            defaultUnitId: InventoryUnitIds.piece,
            quantityDeltaAtomic: 20,
            movementReason: 'initial_stock',
          ),
        );
        final resource =
            (await h.db.select(h.db.inventoryItems).get()).single.id;
        final recipe = [
          CrearArticuloRecipeComponentCommand(
            inventoryItemId: resource,
            quantity: '2',
          ),
        ];
        await h.commands.crearArticulo(
          CrearArticuloCommand.conVariantes(
            nombre: 'Artículo con consumo',
            variantes: [
              variant(
                'Directa',
                [],
                unit: InventoryUnitIds.piece,
                initialStock: '10',
              ),
              variant('Receta', [], recipe: recipe),
            ],
          ),
        );
        final productId = h.appends.last.event.aggregateId;
        final detail = (await h.repository.obtenerDetalle(productId))!;
        sales.config.update(sales.config.config.copyWith(cashEnabled: true));
        await sales.cash.abrir(
          const AbrirCajaCommand(
            sessionId: '00000000-0000-4000-8000-000000000099',
            openingMinor: 0,
          ),
        );
        await sales.add(detail.variantes.first.id!);
        await sales.add(detail.variantes.last.id!);
        await sales.service().guardar(await sales.intent());
        await sales.confirm();
        final before = await contents(h.db);
        for (final name in [
          'sales',
          'sale_items',
          'sale_payments',
          'cash_sessions',
          'cash_movements',
          'quotations',
          'quotation_items',
          'inventory_balances',
          'inventory_movements',
          'recipe_components',
        ]) {
          expect(before[name] as List, isNotEmpty, reason: name);
        }
        await h.commands.actualizarArticulo(
          productId: productId,
          baseEventId: detail.lastEventId!,
          variantIds: detail.variantes.map((v) => v.id).toList(),
          command: CrearArticuloCommand.conVariantes(
            nombre: detail.nombre,
            variantes: [
              variant('Directa', [
                quote(supplier, 0, 1791331200123),
              ], unit: InventoryUnitIds.piece),
              variant('Receta', [
                quote(supplier, 1875, 1791417600456),
              ], recipe: recipe),
            ],
          ),
        );
        final after = await contents(h.db);
        for (final entry in before.entries) {
          if (!{
            'events',
            'products',
            'product_variants',
            'variant_suppliers',
          }.contains(entry.key)) {
            expect(after[entry.key], entry.value, reason: entry.key);
          }
        }
        final saved = (await h.repository.obtenerDetalle(productId))!;
        for (var i = 0; i < 2; i++) {
          expect(
            saved.variantes[i].precioVentaMenor,
            detail.variantes[i].precioVentaMenor,
          );
          expect(
            saved.variantes[i].costoEstandarMenor,
            detail.variantes[i].costoEstandarMenor,
          );
          expect(
            saved.variantes[i].inventoryItemId,
            detail.variantes[i].inventoryItemId,
          );
          expect(
            saved.variantes[i].componentesReceta,
            detail.variantes[i].componentesReceta,
          );
        }
        expect(after['variant_suppliers'] as List, hasLength(2));
        await checkIntegrity(h.db);
        await export('regression-commercial-prices', {
          'unaffected_tables_compared_with_nonempty_rows': [
            'sales',
            'sale_items',
            'sale_payments',
            'cash_sessions',
            'cash_movements',
            'quotations',
            'quotation_items',
            'inventory_balances',
            'inventory_movements',
            'recipe_components',
          ],
          'sale_price_and_standard_cost_preserved': true,
          'before': before,
          'after': after,
        });
      } finally {
        await sales.config.dispose();
        await h.dispose();
      }
    },
  );
}

class _NoNetwork extends HttpOverrides {
  int clients = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('La aceptación local no permite HTTP/WebSocket.');
  }
}
