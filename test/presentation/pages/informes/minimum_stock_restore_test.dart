import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/informes/remaining_stock_screen.dart';
import 'package:pos_flutter/presentation/pages/informes/remaining_stock_variant_editor.dart';

import '../../../support/product_supplier_harness.dart';
import '../../../support/recepcion_masiva_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in AppMode.values) {
    testWidgets(
      'A36/A37 disco y restore integrados conservan aviso, presencia y undo (${mode.name})',
      (tester) async {
        await tester.runAsync(() async {
          final temp = await Directory.systemTemp.createTemp(
            'minimum_restore_',
          );
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path,
          );
          var h = ProductSupplierHarness(database: AppDatabase(), mode: mode);
          try {
            final rows = await seedRecepcion(h);
            final piece = rows.singleWhere((r) => r.nombreVariante == 'Piezas');
            await h.commands.crearArticulo(
              CrearArticuloCommand.conVariantes(
                nombre: 'Medido',
                saleConfiguration: MeasuredSaleConfiguration(
                  saleUnitId: InventoryUnitIds.gram,
                  priceReferenceQuantityAtomic: 1,
                ),
                variantes: const [
                  CrearArticuloVarianteCommand(
                    nombre: null,
                    precioVenta: '1',
                    costoEstandar: null,
                    inventoryUnitId: InventoryUnitIds.kilogram,
                    initialStockQuantity: '1.5',
                    minimumStock: CambioExplicito.establecer('1.5'),
                  ),
                ],
              ),
            );
            const legacyId = 'restore-legacy';
            await h.events.appendAndApply(
              SyncEvent(
                eventId: 'restore-legacy-create',
                aggregateType: 'product',
                aggregateId: legacyId,
                eventType: ProductoCreadoPayload.eventType,
                deviceId: 'old',
                userId: 'user',
                createdAtLocal: DateTime(2026),
                baseVersion: 1,
                payload: ProductoCreadoPayload.create(
                  nombre: 'Legado',
                  saleConfiguration: const UnitSaleConfiguration(),
                  categoriaId: null,
                  variantes: [
                    ProductoCreadoVariante.create(
                      id: 'aaaaaaaa-0000-4000-8000-000000000001',
                      nombre: null,
                      precioVentaMenor: 100,
                      costoEstandarMenor: null,
                      orden: 0,
                      proveedores: [],
                    ),
                  ],
                ).toJson(),
              ),
              refs: [
                const LocalEventRef.affects(
                  refType: 'product',
                  refId: legacyId,
                ),
              ],
            );
            await _show(tester, h);
            await _edit(tester, piece.clave.variantId, '6');
            final before = await fotoRecepcion(h.db);
            final undo = await h.db.select(h.db.productUpdateUndo).get();
            expect(undo.isNotEmpty, mode == AppMode.serverSync);
            await tester.pumpWidget(const SizedBox.shrink());
            await h.dispose();
            h = ProductSupplierHarness(database: AppDatabase(), mode: mode);
            expect(await fotoRecepcion(h.db), before);
            await _show(tester, h);
            _expectRestoredView();
            final snapshot = await DriftDatabaseSnapshotService(
              db: h.db,
              stateReader: DriftDatabaseStateReader(db: h.db),
            ).createSnapshot();
            try {
              await _edit(tester, piece.clave.variantId, '');
              expect(find.text('Existencia baja'), findsOneWidget);
              expect(await fotoRecepcion(h.db), isNot(equals(before)));
              await tester.pumpWidget(const SizedBox.shrink());
              await DriftDatabaseRestoreService(
                db: h.db,
              ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
              await h.tracking.config.dispose();
              h = ProductSupplierHarness(database: AppDatabase(), mode: mode);
              expect(await fotoRecepcion(h.db), before);
              expect(await appDatabaseShouldPreserveRestoredDatabase(), isTrue);
              final legacy = await h.tracking.products.snapshot(legacyId);
              expect(legacy.knowsMinimumStock, isFalse);
              final known = await h.tracking.products.snapshot(
                piece.clave.productId,
              );
              expect(known.knowsMinimumStock, isTrue);
              expect(
                known.variantes.where((v) => v.minimumStockAtomic == null),
                hasLength(2),
              );
              await _show(tester, h);
              _expectRestoredView();
              await tester.tap(find.text('Existencias bajas'));
              await _settle(tester);
              expect(
                find.byKey(ValueKey(piece.clave.variantId)),
                findsOneWidget,
              );
              expect(find.text('Existencia baja'), findsNWidgets(2));
              expect(await fotoRecepcion(h.db), before);
              expect(
                await h.db.customSelect('PRAGMA foreign_key_check').get(),
                isEmpty,
              );
              expect(
                (await h.db.customSelect('PRAGMA integrity_check').get())
                    .single
                    .data
                    .values
                    .single,
                'ok',
              );
              await tester.pumpWidget(const SizedBox.shrink());
              await h.dispose();
              h = ProductSupplierHarness(database: AppDatabase(), mode: mode);
              expect(await fotoRecepcion(h.db), before);
              final refs = await h.db.select(h.db.eventRefs).get();
              if (mode == AppMode.standalone) {
                expect(refs, isEmpty);
                expect(
                  (await h.db.select(h.db.events).get()).every(
                    (e) => e.deliveryStatus == 'not_required',
                  ),
                  isTrue,
                );
              } else {
                expect(refs, isNotEmpty);
              }
            } finally {
              await snapshot.file.parent.delete(recursive: true);
            }
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await h.dispose();
            messenger.setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
            await temp.delete(recursive: true);
          }
        });
      },
    );
  }
}

Future<void> _show(WidgetTester tester, ProductSupplierHarness h) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RemainingStockScreen(
        repository: h.repository,
        variantEditor: RemainingStockVariantEditor(
          repository: h.repository,
          commands: h.commands,
          resources: RecursoInventarioRepositoryImpl(
            inventoryDao: h.db.inventoryDao,
          ),
          units: UnidadInventarioRepositoryImpl(unitDao: h.db.unitDao),
          inventoryCommands: h.tracking.inventoryCommands,
          config: h.tracking.config,
        ),
      ),
    ),
  );
  await _settle(tester);
}

void _expectRestoredView() {
  expect(find.text('Mínimo: 6 pza'), findsOneWidget);
  expect(find.text('Mínimo: 1.5 kg'), findsOneWidget);
  expect(find.text('Existencia baja'), findsNWidgets(2));
  expect(find.text('Existencias bajas: 2'), findsOneWidget);
}

Future<void> _edit(WidgetTester tester, String id, String value) async {
  await tester.ensureVisible(find.byKey(ValueKey(id)));
  await tester.tap(find.byKey(ValueKey(id)));
  await _settle(tester);
  final field = find.byKey(const Key('variant_minimum_stock_field'));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  final save = find.byKey(const Key('save_variant_button'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  // SQLite en disco termina en otro isolate; avanzar solo el reloj virtual
  // puede agotar pumpAndSettle antes de que concluya la transacción real.
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (field.evaluate().isNotEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(field, findsNothing);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}
