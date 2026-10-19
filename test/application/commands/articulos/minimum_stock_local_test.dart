import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/minimum_stock_policy.dart';

import '../../../support/product_supplier_harness.dart';
import '../../../support/recepcion_masiva_fixture.dart';

void main() {
  // Cada base usa su propio executor aislado; las reaperturas cierran el anterior.
  final previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning,
  );
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late ProductSupplierHarness h;
      setUp(() => h = ProductSupplierHarness(mode: mode));
      tearDown(() => h.dispose());

      test(
        'A16/A18/A24/A31/A32 mínimo, no-op, conservar, cero y retirar',
        () async {
          final id = await _create(h);
          final original = await fotoRecepcion(h.db);
          final key = await h.tracking.products.consumptionConfigurationKey(
            (await _state(h, id)).variantes.single.id,
          );
          final appends = h.appends.length;
          await _save(h, id, minimum: const CambioExplicito.establecer('5'));
          expect(h.appends, hasLength(appends + 1));
          final update = h.appends.last;
          final payload = ProductoActualizadoPayload.fromJson(
            update.event.payload,
          );
          expect(payload.before.variantes.single.minimumStockAtomic, isNull);
          expect(payload.after.variantes.single.minimumStockAtomic, 5);
          expect(payload.before.knowsMinimumStock, isTrue);
          expect(payload.after.knowsMinimumStock, isTrue);
          final variant = (await _state(h, id)).variantes.single;
          expect(
            await h.tracking.products.consumptionConfigurationKey(variant.id),
            key,
          );
          final after = await fotoRecepcion(h.db);
          expect(after['inventory_balances'], original['inventory_balances']);
          expect(after['inventory_movements'], original['inventory_movements']);
          expect(
            update.refs.map((r) => r.refType),
            isNot(contains('minimum_stock')),
          );
          expect(
            update.refs.any((r) => r.refType == 'product' && r.refId == id),
            isTrue,
          );
          final stored = (await h.tracking.history.eventById(
            update.event.eventId,
          ))!;
          expect(
            stored.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          expect(
            await h.db.select(h.db.eventRefs).get(),
            mode == AppMode.standalone ? isEmpty : isNotEmpty,
          );
          await _save(h, id, minimum: const CambioExplicito.establecer('5'));
          await _save(h, id);
          expect(await fotoRecepcion(h.db), after);
          await _save(h, id, minimum: const CambioExplicito.establecer('0'));
          expect((await _state(h, id)).variantes.single.minimumStockAtomic, 0);
          await _save(h, id, minimum: const CambioExplicito.establecer(null));
          expect(
            (await _state(h, id)).variantes.single.minimumStockAtomic,
            isNull,
          );
          expect((await _state(h, id)).knowsMinimumStock, isTrue);
          expect(
            (await h.repository.obtenerDetalle(
              id,
            ))!.variantes.single.knowsMinimumStock,
            isTrue,
          );
          final listed = (await h.repository.watchArticulos().first)
              .single
              .variantesActivas
              .single;
          expect(listed.minimumStockAtomic, isNull);
          expect(listed.knowsMinimumStock, isTrue);
          await expectLater(
            h.local.appendAndApply(
              update.event.copyWith(eventId: 'bad-refs'),
              refs: [],
            ),
            throwsArgumentError,
          );
          expect(await h.tracking.history.eventById('bad-refs'), isNull);
        },
      );

      test(
        'A06/A07/A19 unidad de inventario exacta y validación atómica',
        () async {
          final id = await _create(h, measured: true, minimum: '1,5');
          final v = (await _state(h, id)).variantes.single;
          expect(v.minimumStockAtomic, 1500);
          expect(_low(1500, 1500), isTrue);
          expect(_low(1500, 1501), isFalse);
          final before = await fotoRecepcion(h.db);
          for (final input in ['-1', '1.0001', '9007199254740992', '', 'NaN']) {
            await expectLater(
              _save(h, id, minimum: CambioExplicito.establecer(input)),
              throwsFormatException,
            );
            expect(await fotoRecepcion(h.db), before);
          }
          await expectLater(
            _save(
              h,
              id,
              unit: InventoryUnitIds.liter,
              minimum: const CambioExplicito.establecer('1'),
            ),
            throwsStateError,
          );
          expect(await fotoRecepcion(h.db), before);
          final count = await _create(h, name: 'Piezas');
          final countBefore = await fotoRecepcion(h.db);
          await expectLater(
            _save(h, count, minimum: const CambioExplicito.establecer('0.5')),
            throwsFormatException,
          );
          expect(await fotoRecepcion(h.db), countBefore);
          await expectLater(
            _create(h, name: 'Inválido', tracked: false, minimum: '3'),
            throwsFormatException,
          );
          expect(await fotoRecepcion(h.db), countBefore);
        },
      );

      test(
        'A20/A25/A26 barcode, receta, retiro y recuperación conservan umbral dormido',
        () async {
          final id = await _create(h, minimum: '5');
          final first = (await _state(h, id)).variantes.single;
          final p = (await h.tracking.products.findProductById(id))!;
          await h.commands.asignarCodigoBarrasVariante(
            AsignarCodigoBarrasVarianteCommand(
              productId: id,
              variantId: first.id,
              baseEventId: p.lastEventId!,
              codigoBarras: '00123',
            ),
          );
          expect((await _state(h, id)).variantes.single.minimumStockAtomic, 5);
          await _save(h, id, tracked: false);
          final dormant = (await _state(h, id)).variantes.single;
          expect(dormant.minimumStockAtomic, 5);
          expect(dormant.inventoryItemId, isNull);
          final before = await fotoRecepcion(h.db);
          await expectLater(
            _save(
              h,
              id,
              tracked: false,
              minimum: const CambioExplicito.establecer(null),
            ),
            throwsFormatException,
          );
          expect(await fotoRecepcion(h.db), before);
          await _save(
            h,
            id,
            tracked: false,
            recipe: [
              CrearArticuloRecipeComponentCommand(
                inventoryItemId: first.inventoryItemId!,
                quantity: '1',
              ),
            ],
          );
          expect((await _state(h, id)).variantes.single.minimumStockAtomic, 5);
          await _save(h, id);
          final recovered = (await h.repository.watchArticulos().first)
              .single
              .variantesActivas
              .single;
          expect(recovered.inventario!.id, first.inventoryItemId);
          expect(
            _low(
              recovered.minimumStockAtomic,
              recovered.inventario!.existenciaAtomica,
            ),
            isTrue,
          );
          final base = (await h.tracking.products.findProductById(id))!;
          await h.commands.eliminarArticulo(
            productId: id,
            baseEventId: base.lastEventId!,
          );
          expect(
            (await h.db.select(h.db.productVariants).get())
                .single
                .minimumStockAtomic,
            5,
          );
          expect(await h.repository.watchArticulos().first, isEmpty);
          if (mode == AppMode.serverSync) {
            await h.db.transaction(
              () => h.tracking.cleaner.hideConflictProjection(
                h.appends.last.event,
              ),
            );
            expect(
              (await _state(h, id)).variantes.single.minimumStockAtomic,
              5,
            );
          }
        },
      );

      test(
        'A05/A24 cambiar mínimo no invalida consumo capturado en venta abierta',
        () async {
          final id = await _create(h, initial: '6');
          final v = (await _state(h, id)).variantes.single;
          await h.tracking.drafts.agregar(
            AgregarProductoBorradorCommand(variantId: v.id),
          );
          final draft = (await h.db.select(h.db.sales).get()).single;
          await _save(h, id, minimum: const CambioExplicito.establecer('5'));
          await h.tracking.sales.confirmar(
            ConfirmarVentaCommand(
              saleId: draft.id,
              expectedDraftEventId: draft.lastEventId!,
              expectedTotalMinor: draft.totalMinor,
              paymentMethod: 'transfer',
            ),
          );
          final balance =
              (await h.db.select(h.db.inventoryBalances).get()).single;
          expect(balance.quantityOnHandAtomic, 5);
          expect(
            _low(
              (await _state(h, id)).variantes.single.minimumStockAtomic,
              balance.quantityOnHandAtomic,
            ),
            isTrue,
          );
        },
      );

      test(
        'A27/A28 rollback después de proyectar, duplicado y base obsoleta',
        () async {
          final id = await _create(h, minimum: '5');
          final staleBase = (await h.tracking.products.findProductById(
            id,
          ))!.lastEventId!;
          final before = await fotoRecepcion(h.db);
          h.failAfterProductApply = true;
          await expectLater(
            _save(h, id, minimum: const CambioExplicito.establecer('7')),
            throwsStateError,
          );
          h.failAfterProductApply = false;
          expect(await fotoRecepcion(h.db), before);
          await _save(h, id, minimum: const CambioExplicito.establecer('7'));
          final event = h.appends.last.event;
          final after = await fotoRecepcion(h.db);
          await h.tracking.processor.apply(
            (await h.tracking.history.eventById(event.eventId))!,
          );
          expect(await fotoRecepcion(h.db), after);
          await expectLater(
            _save(
              h,
              id,
              minimum: const CambioExplicito.establecer('9'),
              base: staleBase,
            ),
            throwsStateError,
          );
          expect(await fotoRecepcion(h.db), after);
        },
      );

      test(
        'A10/A13–A17 legado conserva presencia, promoción sin evento y rechazo de escritor antiguo',
        () async {
          final id = await _legacy(h);
          expect((await _state(h, id)).knowsMinimumStock, isFalse);
          final before = await fotoRecepcion(h.db);
          await _save(h, id, minimum: const CambioExplicito.establecer(null));
          expect(await fotoRecepcion(h.db), before);
          // Un escritor legado todavía puede cambiar la base realmente legada.
          final legacy = await _state(h, id);
          final changed = ProductoCreadoPayload.create(
            nombre: 'Legado editado',
            saleConfiguration: legacy.saleConfiguration,
            categoriaId: null,
            variantes: legacy.variantes,
            dependenciasInventario: legacy.dependenciasInventario,
          );
          await _applyUpdate(h, id, legacy, changed, 'legacy-update');
          expect((await _state(h, id)).knowsMinimumStock, isFalse);
          await _save(h, id, minimum: const CambioExplicito.establecer('5'));
          expect((await _state(h, id)).knowsMinimumStock, isTrue);
          final current = await _state(h, id);
          final currentProduct = (await h.tracking.products.findProductById(
            id,
          ))!;
          for (final delete in [false, true]) {
            final legacyBefore = _omitMinimum(current);
            await expectLater(
              h.events.appendAndApply(
                SyncEvent(
                  eventId: 'legacy-degrade-$delete',
                  aggregateType: 'product',
                  aggregateId: id,
                  eventType: ProductoActualizadoPayload.eventType,
                  deviceId: 'old',
                  userId: 'user',
                  baseVersion: currentProduct.version,
                  createdAtLocal: DateTime(2026),
                  payload: ProductoActualizadoPayload(
                    baseEventId: currentProduct.lastEventId!,
                    before: legacyBefore,
                    after: legacyBefore,
                    deleteProduct: delete,
                  ).toJson(),
                ),
                refs: [LocalEventRef.affects(refType: 'product', refId: id)],
              ),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'actualizar',
                  contains('Actualiza la app'),
                ),
              ),
            );
            expect((await _state(h, id)).toJson(), current.toJson());
          }
          await _save(h, id, minimum: const CambioExplicito.establecer(null));
          final knownNull = await _state(h, id);
          expect(knownNull.knowsMinimumStock, isTrue);
          await expectLater(
            _applyUpdate(
              h,
              id,
              _omitMinimum(knownNull),
              _omitMinimum(knownNull),
              'old-over-known-null',
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'actualizar',
                contains('Actualiza la app'),
              ),
            ),
          );
        },
      );

      test(
        'A29/A30 undo recupera ausencia exacta y una restauración tardía respeta base posterior',
        () async {
          final id = await _legacy(h);
          final legacy = await _state(h, id);
          await _save(h, id, minimum: const CambioExplicito.establecer('5'));
          final failed = (await h.tracking.history.eventById(
            h.appends.last.event.eventId,
          ))!;
          await h.db.transaction(() async {
            await h.tracking.cleaner.hideConflictProjection(failed);
            await (h.db.update(
              h.db.events,
            )..where((e) => e.eventId.equals(failed.eventId))).write(
              EventsCompanion(
                deliveryStatus: Value(
                  mode == AppMode.serverSync ? 'conflict' : 'not_required',
                ),
              ),
            );
          });
          expect((await _state(h, id)).toJson(), legacy.toJson());
          expect(
            (await h.repository.obtenerDetalle(
              id,
            ))!.variantes.single.knowsMinimumStock,
            isFalse,
          );
          await _save(h, id, minimum: const CambioExplicito.establecer('7'));
          final earlier = (await h.tracking.history.eventById(
            h.appends.last.event.eventId,
          ))!;
          await _save(h, id, minimum: const CambioExplicito.establecer('9'));
          final accepted = await _state(h, id);
          final product = (await h.tracking.products.findProductById(id))!;
          // Marca aceptación local aislada; no se invoca transporte remoto.
          if (mode == AppMode.serverSync) {
            await (h.db.update(
              h.db.events,
            )..where((e) => e.eventId.equals(product.lastEventId!))).write(
              const EventsCompanion(
                deliveryStatus: Value('delivered'),
                serverSequence: Value(20),
              ),
            );
          }
          await h.db.transaction(
            () => h.tracking.cleaner.hideConflictProjection(earlier),
          );
          expect((await _state(h, id)).toJson(), accepted.toJson());
          expect((await _state(h, id)).variantes.single.minimumStockAtomic, 9);
        },
      );

      test(
        'A23/A41 repositorio observable y recepción evalúan saldo vigente sin eventos de alerta',
        () async {
          final rows = await seedRecepcion(h);
          final first = rows.singleWhere((r) => r.nombreVariante == 'Piezas');
          final stream = StreamIterator(h.repository.watchArticulos());
          try {
            await stream.moveNext();
            final initial = stream.current.single.variantesActivas.singleWhere(
              (v) => v.varianteId == first.clave.variantId,
            );
            expect(
              _low(
                initial.minimumStockAtomic,
                initial.inventario!.existenciaAtomica,
              ),
              isTrue,
            );
            final service = coordinadorRecepcion(h);
            final operations = await service.confirmar(
              batchId: 'minimum-receipt',
              cambios: [cambioRecepcion(first, venta: 2500, cantidad: 1)],
            );
            final result = await service.ejecutar(operations.single);
            await stream.moveNext();
            final received = stream.current.single.variantesActivas.singleWhere(
              (v) => v.varianteId == first.clave.variantId,
            );
            expect(received.minimumStockAtomic, 5);
            expect(received.inventario!.existenciaAtomica, 6);
            expect(
              _low(
                received.minimumStockAtomic,
                received.inventario!.existenciaAtomica,
              ),
              isFalse,
            );
            final emitted = await service.eventos(result);
            expect(emitted.map((e) => e.eventType).toSet(), {
              'producto_actualizado',
              'movimiento_inventario_registrado',
            });
          } finally {
            await stream.cancel();
          }
        },
      );

      test(
        'A19/A26/A28 variantes comparten base y retirada conserva mínimo',
        () async {
          await h.commands.crearArticulo(
            const CrearArticuloCommand.conVariantes(
              nombre: 'Avanzado',
              variantes: [
                CrearArticuloVarianteCommand(
                  nombre: 'A',
                  precioVenta: '10',
                  costoEstandar: null,
                  inventoryUnitId: InventoryUnitIds.piece,
                  initialStockQuantity: '5',
                  minimumStock: CambioExplicito.establecer('5'),
                ),
                CrearArticuloVarianteCommand(
                  nombre: 'B',
                  precioVenta: '10',
                  costoEstandar: null,
                  inventoryUnitId: InventoryUnitIds.piece,
                  initialStockQuantity: '5',
                  minimumStock: CambioExplicito.establecer('0'),
                ),
              ],
            ),
          );
          final id = h.appends.last.event.aggregateId;
          final initial = await _state(h, id);
          final base = (await h.tracking.products.findProductById(
            id,
          ))!.lastEventId!;
          Future<void> save(
            String eventBase, {
            bool remove = false,
            bool second = false,
          }) async {
            await h.commands.actualizarArticulo(
              productId: id,
              baseEventId: eventBase,
              variantIds: [
                for (final v in initial.variantes)
                  if (!remove || v.orden == 1) v.id,
              ],
              command: CrearArticuloCommand.conVariantes(
                nombre: initial.nombre,
                variantes: [
                  for (final v in initial.variantes)
                    if (!remove || v.orden == 1)
                      CrearArticuloVarianteCommand(
                        nombre: v.nombre,
                        precioVenta: '10',
                        costoEstandar: null,
                        inventoryUnitId: InventoryUnitIds.piece,
                        minimumStock: v.orden == (second ? 1 : 0)
                            ? const CambioExplicito.establecer('7')
                            : const CambioExplicito.conservar(),
                      ),
                ],
              ),
            );
          }

          await save(base);
          final state = await _state(h, id);
          expect(state.variantes.map((v) => v.minimumStockAtomic), [7, 0]);
          final beforeConflict = await fotoRecepcion(h.db);
          await expectLater(save(base, second: true), throwsStateError);
          expect(await fotoRecepcion(h.db), beforeConflict);
          final latest = (await h.tracking.products.findProductById(
            id,
          ))!.lastEventId!;
          await save(latest, remove: true);
          final retired = await h.db.productoDao.obtenerVariantePorId(
            initial.variantes.first.id,
          );
          expect(retired!.active, isFalse);
          expect(retired.minimumStockAtomic, 7);
          expect((await _state(h, id)).variantes.single.minimumStockAtomic, 0);
          if (mode == AppMode.serverSync) {
            await h.db.transaction(
              () => h.tracking.cleaner.hideConflictProjection(
                h.appends.last.event,
              ),
            );
            expect((await _state(h, id)).toJson(), state.toJson());
          }
        },
      );

      test(
        'A34 reproducción legada seguida de actual y duplicados conserva estado',
        () async {
          final id = await _legacy(h);
          await _save(h, id, minimum: const CambioExplicito.establecer('0'));
          await _save(h, id, minimum: const CambioExplicito.establecer('5'));
          final state = await _state(h, id);
          final history = await h.tracking.storedEvents();
          final replay = ProductSupplierHarness(mode: mode);
          try {
            for (final event in history) {
              await replay.events.appendAndApply(
                event,
                refs: [
                  LocalEventRef.affects(
                    refType: event.aggregateType,
                    refId: event.aggregateId,
                  ),
                ],
              );
            }
            await replay.tracking.processor.apply(history.last);
            await replay.tracking.processor.apply(
              history.firstWhere(
                (e) => e.eventType == ProductoCreadoPayload.eventType,
              ),
            );
            expect((await _state(replay, id)).toJson(), state.toJson());
            expect(
              (await replay.db.select(replay.db.inventoryBalances).get())
                  .single
                  .quantityOnHandAtomic,
              5,
            );
          } finally {
            await replay.dispose();
          }
        },
      );

      test(
        'A15 valor físico con metadata legada impide borrado silencioso',
        () async {
          final id = await _legacy(h);
          final legacy = await _state(h, id);
          await (h.db.update(
            h.db.productVariants,
          )..where((v) => v.productId.equals(id))).write(
            const ProductVariantsCompanion(minimumStockAtomic: Value(5)),
          );
          final current = await _state(h, id);
          expect(current.knowsMinimumStock, isTrue);
          expect(current.variantes.single.minimumStockAtomic, 5);
          final before = await fotoRecepcion(h.db);
          await expectLater(
            _applyUpdate(h, id, legacy, legacy, 'legacy-over-physical'),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'actualizar',
                contains('Actualiza la app'),
              ),
            ),
          );
          expect(await fotoRecepcion(h.db), before);
        },
      );

      test(
        'A37/A41 reapertura en disco conserva valores, conocimiento y lecturas puras',
        () async {
          final temp = await Directory.systemTemp.createTemp(
            'minimum_stock_local_',
          );
          var disk = ProductSupplierHarness(
            database: AppDatabase.forTesting(
              NativeDatabase(File('${temp.path}/pos.sqlite')),
            ),
            mode: mode,
          );
          try {
            final legacyId = await _legacy(disk);
            final currentId = await _create(disk, minimum: '5');
            final nullId = await _create(disk, name: 'Null conocido');
            final before = await fotoRecepcion(disk.db);
            await disk.dispose();
            disk = ProductSupplierHarness(
              database: AppDatabase.forTesting(
                NativeDatabase(File('${temp.path}/pos.sqlite')),
              ),
              mode: mode,
            );
            expect((await _state(disk, legacyId)).knowsMinimumStock, isFalse);
            expect((await _state(disk, nullId)).knowsMinimumStock, isTrue);
            for (var i = 0; i < 3; i++) {
              final v = (await _state(disk, currentId)).variantes.single;
              final detail = (await disk.repository.obtenerDetalle(
                currentId,
              ))!.variantes.single;
              final rows = await disk.repository.watchArticulos().first;
              expect(detail.minimumStockAtomic, 5);
              expect(
                rows
                    .singleWhere((r) => r.productoId == currentId)
                    .variantesActivas
                    .single
                    .knowsMinimumStock,
                isTrue,
              );
              expect(_low(v.minimumStockAtomic, 5), isTrue);
            }
            expect(await fotoRecepcion(disk.db), before);
            disk.failAfterProductApply = true;
            await expectLater(
              _save(
                disk,
                legacyId,
                minimum: const CambioExplicito.establecer('3'),
              ),
              throwsStateError,
            );
            disk.failAfterProductApply = false;
            expect(await fotoRecepcion(disk.db), before);
            await _save(
              disk,
              legacyId,
              minimum: const CambioExplicito.establecer('3'),
            );
            final failed = (await disk.tracking.history.eventById(
              disk.appends.last.event.eventId,
            ))!;
            await _save(
              disk,
              nullId,
              minimum: const CambioExplicito.establecer('4'),
            );
            final knownNull = (await disk.tracking.history.eventById(
              disk.appends.last.event.eventId,
            ))!;
            await disk.dispose();
            disk = ProductSupplierHarness(
              database: AppDatabase.forTesting(
                NativeDatabase(File('${temp.path}/pos.sqlite')),
              ),
              mode: mode,
            );
            await disk.db.transaction(() async {
              await disk.tracking.cleaner.hideConflictProjection(failed);
              await disk.tracking.cleaner.hideConflictProjection(knownNull);
              await (disk.db.update(disk.db.events)..where(
                    (e) => e.eventId.isIn([failed.eventId, knownNull.eventId]),
                  ))
                  .write(
                    EventsCompanion(
                      deliveryStatus: Value(
                        mode == AppMode.serverSync
                            ? 'rejected'
                            : 'not_required',
                      ),
                    ),
                  );
            });
            expect((await _state(disk, legacyId)).knowsMinimumStock, isFalse);
            expect((await _state(disk, nullId)).knowsMinimumStock, isTrue);
            expect(
              (await _state(disk, nullId)).variantes.single.minimumStockAtomic,
              isNull,
            );
            await _save(
              disk,
              currentId,
              minimum: const CambioExplicito.establecer('7'),
            );
            final oldUpdate = (await disk.tracking.history.eventById(
              disk.appends.last.event.eventId,
            ))!;
            await _save(
              disk,
              currentId,
              minimum: const CambioExplicito.establecer('9'),
            );
            final latest = (await disk.tracking.history.eventById(
              disk.appends.last.event.eventId,
            ))!;
            if (mode == AppMode.serverSync) {
              await (disk.db.update(
                disk.db.events,
              )..where((e) => e.eventId.equals(latest.eventId))).write(
                const EventsCompanion(
                  deliveryStatus: Value('delivered'),
                  serverSequence: Value(30),
                ),
              );
            }
            await disk.dispose();
            disk = ProductSupplierHarness(
              database: AppDatabase.forTesting(
                NativeDatabase(File('${temp.path}/pos.sqlite')),
              ),
              mode: mode,
            );
            await disk.db.transaction(
              () => disk.tracking.cleaner.hideConflictProjection(oldUpdate),
            );
            await disk.tracking.processor.apply(latest);
            expect(
              (await _state(
                disk,
                currentId,
              )).variantes.single.minimumStockAtomic,
              9,
            );
            final finalState = await fotoRecepcion(disk.db);
            await disk.dispose();
            disk = ProductSupplierHarness(
              database: AppDatabase.forTesting(
                NativeDatabase(File('${temp.path}/pos.sqlite')),
              ),
              mode: mode,
            );
            expect(await fotoRecepcion(disk.db), finalState);
            expect((await _state(disk, legacyId)).knowsMinimumStock, isFalse);
            expect((await _state(disk, nullId)).knowsMinimumStock, isTrue);
          } finally {
            await disk.dispose();
            await temp.delete(recursive: true);
          }
        },
      );
    });
  }

  test(
    'A01–A03/A26 regla compartida excluye inactivos, recetas y recursos no disponibles',
    () {
      for (final balance in [-1, 0, 5]) {
        expect(_low(null, balance), isFalse);
      }
      expect([6, 5, 4].map((b) => _low(5, b)), [false, true, true]);
      expect([1, 0, -1].map((b) => _low(0, b)), [false, true, true]);
      for (var disabled = 0; disabled < 4; disabled++) {
        expect(
          const MinimumStockPolicy().isLow(
            minimumStockAtomic: 5,
            quantityOnHandAtomic: 0,
            productActive: disabled != 0,
            variantActive: disabled != 1,
            hasDirectTracking: disabled != 2,
            inventoryItemActive: disabled != 3,
          ),
          isFalse,
        );
      }
    },
  );
}

bool _low(int? minimum, int balance) => const MinimumStockPolicy().isLow(
  minimumStockAtomic: minimum,
  quantityOnHandAtomic: balance,
  productActive: true,
  variantActive: true,
  hasDirectTracking: true,
  inventoryItemActive: true,
);

Future<ProductoCreadoPayload> _state(ProductSupplierHarness h, String id) =>
    h.tracking.products.snapshot(id);

Future<String> _create(
  ProductSupplierHarness h, {
  String name = 'Producto',
  String initial = '5',
  String? minimum,
  bool measured = false,
  bool tracked = true,
}) async {
  await h.commands.crearArticulo(
    CrearArticuloCommand.conVariantes(
      nombre: name,
      saleConfiguration: measured
          ? MeasuredSaleConfiguration(
              saleUnitId: InventoryUnitIds.gram,
              priceReferenceQuantityAtomic: 1,
            )
          : const UnitSaleConfiguration(),
      variantes: [
        CrearArticuloVarianteCommand(
          nombre: null,
          precioVenta: '10',
          costoEstandar: null,
          inventoryUnitId: tracked
              ? (measured ? InventoryUnitIds.kilogram : InventoryUnitIds.piece)
              : null,
          initialStockQuantity: tracked ? initial : null,
          minimumStock: minimum == null
              ? const CambioExplicito.conservar()
              : CambioExplicito.establecer(minimum),
        ),
      ],
    ),
  );
  return h.appends.last.event.aggregateId;
}

Future<void> _save(
  ProductSupplierHarness h,
  String id, {
  CambioExplicito<String?> minimum = const CambioExplicito.conservar(),
  bool tracked = true,
  String? unit,
  String? base,
  List<CrearArticuloRecipeComponentCommand> recipe = const [],
}) async {
  final state = await _state(h, id);
  final p = (await h.tracking.products.findProductById(id))!;
  final v = state.variantes.single;
  await h.commands.actualizarArticulo(
    productId: id,
    baseEventId: base ?? p.lastEventId!,
    variantIds: [v.id],
    command: CrearArticuloCommand.conVariantes(
      nombre: state.nombre,
      saleConfiguration: state.saleConfiguration,
      variantes: [
        CrearArticuloVarianteCommand(
          nombre: v.nombre,
          precioVenta: '10',
          costoEstandar: null,
          codigoBarras: v.codigoBarras,
          inventoryUnitId: tracked
              ? (unit ??
                    (p.saleConfiguration is MeasuredSaleConfiguration
                        ? InventoryUnitIds.kilogram
                        : InventoryUnitIds.piece))
              : null,
          minimumStock: minimum,
          recipeComponents: recipe,
        ),
      ],
    ),
  );
}

ProductoCreadoPayload _omitMinimum(ProductoCreadoPayload state) {
  final json = state.toJson();
  for (final v in (json['variants'] as List).cast<Map<String, Object?>>()) {
    v.remove('minimum_stock_atomic');
  }
  return ProductoCreadoPayload.fromJson(json);
}

Future<String> _legacy(ProductSupplierHarness h) async {
  await h.tracking.inventoryCommands.crearRecurso(
    const CrearRecursoInventarioCommand(
      nombre: 'Recurso legado',
      defaultUnitId: InventoryUnitIds.piece,
      quantityDeltaAtomic: 5,
    ),
  );
  final item = (await h.db.select(h.db.inventoryItems).get()).last;
  const id = 'legacy-product';
  final state = ProductoCreadoPayload.create(
    nombre: 'Legado',
    saleConfiguration: const UnitSaleConfiguration(),
    categoriaId: null,
    variantes: [
      ProductoCreadoVariante.create(
        id: 'aaaaaaaa-0000-4000-8000-000000000001',
        nombre: null,
        precioVentaMenor: 1000,
        costoEstandarMenor: null,
        orden: 0,
        inventoryItemId: item.id,
        proveedores: [],
      ),
    ],
    dependenciasInventario: [
      ProductoCreadoInventarioDependencia(refId: item.id),
    ],
  );
  await h.events.appendAndApply(
    SyncEvent(
      eventId: 'legacy-create',
      aggregateType: 'product',
      aggregateId: id,
      eventType: ProductoCreadoPayload.eventType,
      deviceId: 'old',
      userId: 'user',
      createdAtLocal: DateTime(2026),
      baseVersion: 1,
      payload: state.toJson(),
    ),
    refs: [const LocalEventRef.affects(refType: 'product', refId: id)],
  );
  return id;
}

Future<void> _applyUpdate(
  ProductSupplierHarness h,
  String id,
  ProductoCreadoPayload before,
  ProductoCreadoPayload after,
  String eventId,
) async {
  final p = (await h.tracking.products.findProductById(id))!;
  await h.events.appendAndApply(
    SyncEvent(
      eventId: eventId,
      aggregateType: 'product',
      aggregateId: id,
      eventType: ProductoActualizadoPayload.eventType,
      deviceId: 'writer',
      userId: 'user',
      createdAtLocal: DateTime(2026),
      baseVersion: p.version,
      payload: ProductoActualizadoPayload(
        baseEventId: p.lastEventId!,
        before: before,
        after: after,
      ).toJson(),
    ),
    refs: [LocalEventRef.affects(refType: 'product', refId: id)],
  );
}
