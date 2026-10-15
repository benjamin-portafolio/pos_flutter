import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

import '../../../support/product_supplier_harness.dart';

typedef _Target = ({String productId, String variantId, String baseEventId});

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late Directory directory;
      late File file;
      late ProductSupplierHarness h;

      setUp(() async {
        directory = await Directory.systemTemp.createTemp('pos_barcode_');
        file = File('${directory.path}/catalog.sqlite');
        h = ProductSupplierHarness(
          database: AppDatabase.forTesting(NativeDatabase(file)),
          mode: mode,
        );
      });

      tearDown(() async {
        await h.dispose();
        await directory.delete(recursive: true);
      });

      test(
        'asigna normalizado, conserva ceros y reaplica idempotentemente',
        () async {
          final target = await _create(h);
          final before = await h.tracking.products.snapshot(target.productId);
          final eventCount = (await h.db.select(h.db.events).get()).length;

          await _assign(h, target, '  ０１２３４５６７８９０５  ');

          final event = h.appends.last.event;
          final payload = ProductoActualizadoPayload.fromJson(event.payload);
          expect(event.eventType, ProductoActualizadoPayload.eventType);
          expect(event.aggregateType, ProductoActualizadoPayload.aggregateType);
          expect(event.aggregateId, target.productId);
          expect(event.deviceId, h.tracking.context.deviceId);
          expect(event.userId, h.tracking.context.userId);
          expect(event.baseVersion, 1);
          expect(payload.baseEventId, target.baseEventId);
          expect(payload.before.toJson(), before.toJson());
          expect(payload.after.variantes.single.codigoBarras, '012345678905');
          expect(
            await h.db.select(h.db.events).get(),
            hasLength(eventCount + 1),
          );
          final product = (await h.tracking.products.findProductById(
            target.productId,
          ))!;
          expect(product.version, 2);
          expect(product.lastEventId, event.eventId);
          final detail = (await h.repository.obtenerDetalle(target.productId))!;
          expect(detail.variantes.single.codigoBarras, '012345678905');
          expect(detail.lastEventId, event.eventId);
          expect(
            (await h.repository.buscarVariantesPorCodigoBarras(
              ' ０１２３４５６７８９０５ ',
            )).single.varianteId,
            target.variantId,
          );

          final persisted = (await h.db.eventDao.obtenerEventoPorId(
            event.eventId,
          ))!;
          expect(persisted.applicationStatus, 'applied');
          expect(
            persisted.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          final refs = h.appends.last.refs;
          expect(refs.map(_refKey).toSet(), {
            'product:${target.productId}:affects',
            'product_variant:${target.variantId}:affects',
            'recipe:${target.variantId}:affects',
            'variant_suppliers:${target.variantId}:affects',
          });
          final persistedRefs = await h.db.select(h.db.eventRefs).get();
          if (mode == AppMode.standalone) {
            expect(persistedRefs, isEmpty);
            expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
            expect(await h.db.select(h.db.productUpdateUndo).get(), isEmpty);
          } else {
            expect(
              persistedRefs
                  .where((r) => r.eventId == event.eventId)
                  .map((r) => '${r.refType}:${r.refId}:${r.relationship}')
                  .toSet(),
              refs.map(_refKey).toSet(),
            );
            expect(
              persistedRefs.every((r) => r.source == 'local_pending'),
              isTrue,
            );
            expect(
              await h.db.select(h.db.productUpdateUndo).get(),
              hasLength(1),
            );
          }
          final state = await _databaseState(h.db);
          final applied = event.copyWith(
            deliveryStatus: persisted.deliveryStatus,
          );
          await h.db.transaction(() => h.tracking.processor.apply(applied));
          await h.db.transaction(() => h.tracking.processor.apply(applied));
          expect(await _databaseState(h.db), state);
        },
      );

      test(
        'reemplaza solo el destino, permite compartidos y persiste al reabrir',
        () async {
          final created = await _create(
            h,
            command: CrearArticuloCommand.conVariantes(
              nombre: 'Presentaciones',
              variantes: [
                _variant(name: 'Primera', barcode: '001'),
                _variant(name: 'Segunda', barcode: '001'),
                _variant(name: 'Tercera', barcode: '002'),
              ],
            ),
          );
          final before = await h.tracking.products.snapshot(created.productId);
          final target = (
            productId: created.productId,
            variantId: before.variantes[1].id,
            baseEventId: created.baseEventId,
          );
          await _assign(h, target, '002');
          final payload = ProductoActualizadoPayload.fromJson(
            h.appends.last.event.payload,
          );
          final eventId = h.appends.last.event.eventId;
          _expectOnlyBarcodeChanged(payload, target.variantId, '002');
          expect(payload.before.toJson(), before.toJson());
          final state = await _databaseState(h.db);

          await h.dispose();
          h = ProductSupplierHarness(
            database: AppDatabase.forTesting(NativeDatabase(file)),
            mode: mode,
          );
          expect(await _databaseState(h.db), state);
          expect(
            (await h.tracking.products.snapshot(target.productId)).toJson(),
            payload.after.toJson(),
          );
          expect(
            (await h.repository.buscarVariantesPorCodigoBarras(
              '001',
            )).map((v) => v.varianteId).toSet(),
            {before.variantes.first.id},
          );
          expect(
            (await h.repository.buscarVariantesPorCodigoBarras(
              '002',
            )).map((v) => v.varianteId).toSet(),
            {target.variantId, before.variantes[2].id},
          );
          final saved = (await h.db.eventDao.obtenerEventoPorId(eventId))!;
          final restoredPayload = ProductoActualizadoPayload.fromJson(
            Map<String, Object?>.from(jsonDecode(saved.payload) as Map),
          );
          expect(restoredPayload.before.variantes[1].codigoBarras, '001');
          expect(restoredPayload.after.variantes[1].codigoBarras, '002');
        },
      );

      test('mismo código normalizado no escribe ni cambia metadatos', () async {
        final target = await _create(
          h,
          command: CrearArticuloCommand.conVariantes(
            nombre: 'Sin cambio',
            variantes: [_variant(barcode: '001')],
          ),
        );
        final state = await _databaseState(h.db);
        final appends = h.appends.length;
        await _assign(h, target, ' ００１ ');
        expect(await _databaseState(h.db), state);
        expect(h.appends, hasLength(appends));
      });

      for (final code in [
        '',
        '   ',
        '\u3000',
        'ABC123',
        '12-34',
        '12 34',
        '12.3',
        '+123',
        '١٢٣',
        '1' * 33,
      ]) {
        test(
          'rechaza entrada inválida ${jsonEncode(code)} sin escribir',
          () async {
            final target = await _create(h);
            final state = await _databaseState(h.db);
            final appends = h.appends.length;
            await expectLater(_assign(h, target, code), throwsArgumentError);
            expect(await _databaseState(h.db), state);
            expect(h.appends, hasLength(appends));
          },
        );
      }

      for (final code in ['0', '0' * 32]) {
        test('admite el límite de ${code.length} dígitos como texto', () async {
          final target = await _create(h);
          await _assign(h, target, code);
          expect(
            (await h.repository.obtenerDetalle(
              target.productId,
            ))!.variantes.single.codigoBarras,
            code,
          );
        });
      }

      for (final unavailable in [
        'producto ausente',
        'producto inactivo',
        'variante ausente',
        'variante inactiva',
        'variante ajena',
      ]) {
        test('rechaza $unavailable sin escribir', () async {
          var target = await _create(h);
          switch (unavailable) {
            case 'producto ausente':
              target = (
                productId: 'ausente',
                variantId: target.variantId,
                baseEventId: target.baseEventId,
              );
            case 'producto inactivo':
              await (h.db.update(h.db.products)
                    ..where((p) => p.id.equals(target.productId)))
                  .write(const ProductsCompanion(active: Value(false)));
            case 'variante ausente':
              target = (
                productId: target.productId,
                variantId: 'ausente',
                baseEventId: target.baseEventId,
              );
            case 'variante inactiva':
              await (h.db.update(h.db.productVariants)
                    ..where((v) => v.id.equals(target.variantId)))
                  .write(const ProductVariantsCompanion(active: Value(false)));
            case 'variante ajena':
              final other = await _create(h);
              target = (
                productId: target.productId,
                variantId: other.variantId,
                baseEventId: target.baseEventId,
              );
          }
          final state = await _databaseState(h.db);
          final appends = h.appends.length;
          await expectLater(_assign(h, target, '001'), throwsStateError);
          expect(await _databaseState(h.db), state);
          expect(h.appends, hasLength(appends));
        });
      }

      test('rechaza base obsoleta incluso si el código ya es igual', () async {
        final target = await _create(h);
        await _assign(h, target, '001');
        final state = await _databaseState(h.db);
        for (final code in ['002', '001']) {
          await expectLater(_assign(h, target, code), throwsStateError);
          expect(await _databaseState(h.db), state);
        }
      });

      test('rechaza evento base vacío sin escribir', () async {
        final target = await _create(h);
        final state = await _databaseState(h.db);
        await expectLater(
          _assign(h, (
            productId: target.productId,
            variantId: target.variantId,
            baseEventId: '',
          ), '001'),
          throwsStateError,
        );
        expect(await _databaseState(h.db), state);
      });

      for (final measured in [false, true]) {
        test(
          'conserva snapshot completo, inventario y venta (medido=$measured)',
          () async {
            final target = await _complexProduct(h, measured: measured);
            final before = await h.tracking.products.snapshot(target.productId);
            final state = await _databaseState(h.db);
            final variantRows = await h.db.select(h.db.productVariants).get();
            final count = h.appends.length;
            await _assign(h, target, '0099');
            expect(h.appends, hasLength(count + 1));
            final payload = ProductoActualizadoPayload.fromJson(
              h.appends.last.event.payload,
            );
            expect(payload.before.toJson(), before.toJson());
            _expectOnlyBarcodeChanged(payload, target.variantId, '0099');
            expect(
              ProductoActualizadoPayload.sameState(
                await h.tracking.products.snapshot(target.productId),
                payload.after,
              ),
              isTrue,
            );
            final after = await _databaseState(h.db);
            for (final table in state.keys.where(
              (key) => !{
                'products',
                'product_variants',
                'events',
                'event_refs',
                'product_update_undo',
              }.contains(key),
            )) {
              expect(after[table], state[table], reason: 'Conservar $table');
            }
            for (final row in await h.db.select(h.db.productVariants).get()) {
              final original = variantRows.singleWhere((v) => v.id == row.id);
              expect(row.createdEventId, original.createdEventId);
              if (!original.active) {
                expect(row, original);
              }
            }
            final refs = h.appends.last.refs.map(_refKey).toSet();
            expect(refs, contains('category:category:uses'));
            expect(
              refs.where((r) => r.startsWith('inventory_item:')),
              hasLength(2),
            );
            expect(refs.where((r) => r.startsWith('supplier:')), hasLength(2));
            expect(
              refs.where((r) => r.startsWith('variant_suppliers:')),
              hasLength(3),
            );
            expect(
              refs.where((r) => r.startsWith('product_variant_name:')),
              hasLength(3),
            );
            expect(refs.any((r) => r.contains('barcode')), isFalse);
            if (measured) {
              expect(refs, contains('unit:${InventoryUnitIds.kilogram}:uses'));
            }
            expect(
              payload.after.dependenciasProveedores.every(
                (d) =>
                    (d.dependsOnEventId != null) ==
                    (mode == AppMode.serverSync),
              ),
              isTrue,
            );
            expect(
              payload.after.dependenciasInventario.every(
                (d) =>
                    (d.dependsOnEventId != null) ==
                    (mode == AppMode.serverSync),
              ),
              isTrue,
            );
            await h.dispose();
            h = ProductSupplierHarness(
              database: AppDatabase.forTesting(NativeDatabase(file)),
              mode: mode,
            );
            expect(await _databaseState(h.db), after);
          },
        );
      }

      test(
        'conserva suppliers legado ausente sin promoverlo a lista vacía',
        () async {
          final variant = ProductoCreadoVariante.create(
            id: '00000000-0000-4000-8000-000000000001',
            nombre: null,
            precioVentaMenor: 100,
            costoEstandarMenor: null,
            orden: 0,
          );
          final payload = ProductoCreadoPayload.create(
            nombre: 'Legado',
            categoriaId: null,
            saleConfiguration: const UnitSaleConfiguration(),
            variantes: [variant],
          );
          // Una creación legada real, aplicada por el handler vigente.
          final target = await _create(h);
          final template = h.appends.last.event;
          final legacy = template.copyWith(
            eventId: 'legacy-event',
            aggregateId: 'legacy-product',
            payload: payload.toJson(),
          );
          await h.local.appendAndApply(
            legacy,
            refs: const [
              LocalEventRef.affects(
                refType: 'product',
                refId: 'legacy-product',
              ),
            ],
          );
          await _assign(h, (
            productId: legacy.aggregateId,
            variantId: variant.id,
            baseEventId: legacy.eventId,
          ), '001');
          final update = ProductoActualizadoPayload.fromJson(
            h.appends.last.event.payload,
          );
          expect(update.before.variantes.single.proveedores, isNull);
          expect(update.after.variantes.single.proveedores, isNull);
          expect(
            update.after.toJson()['variants'],
            everyElement(isNot(contains('suppliers'))),
          );
          expect(
            (await h.tracking.products.snapshot(
              legacy.aggregateId,
            )).variantes.single.proveedores,
            isNull,
          );
          expect(
            (await h.tracking.products.snapshot(
              target.productId,
            )).variantes.single.codigoBarras,
            isNull,
          );
        },
      );

      for (final failure in ['persistencia', 'aplicación', 'base al aplicar']) {
        test(
          'rollback íntegro ante fallo de $failure y permite reintento',
          () async {
            final target = await _complexProduct(h);
            final state = await _databaseState(h.db);
            if (failure == 'persistencia') {
              await h.db.customStatement("""
              CREATE TRIGGER injected BEFORE INSERT ON events
              WHEN NEW.event_type = 'producto_actualizado'
              BEGIN SELECT RAISE(ABORT, 'fallo de persistencia'); END
            """);
            } else if (failure == 'base al aplicar') {
              await h.db.customStatement("""
              CREATE TRIGGER injected AFTER INSERT ON events
              WHEN NEW.event_type = 'producto_actualizado'
              BEGIN UPDATE products SET last_event_id = 'otra-base', version = version + 1
                WHERE id = NEW.aggregate_id; END
            """);
            } else {
              h.failAfterProductApply = true;
            }
            await expectLater(
              _assign(h, target, '0099'),
              failure == 'persistencia'
                  ? throwsA(isA<Exception>())
                  : throwsStateError,
            );
            expect(await _databaseState(h.db), state);
            if (failure != 'aplicación') {
              await h.db.customStatement('DROP TRIGGER injected');
            }
            h.failAfterProductApply = false;
            await _assign(h, target, '0099');
            expect(
              (await h.repository.obtenerDetalle(
                target.productId,
              ))!.variantes.first.codigoBarras,
              '0099',
            );
          },
        );
      }

      test(
        'el almacén valida referencias también cuando no las persiste',
        () async {
          final target = await _create(h);
          await _assign(h, target, '001');
          final event = h.appends.last.event.copyWith(eventId: 'without-refs');
          final state = await _databaseState(h.db);
          await expectLater(
            h.local.appendAndApply(event, refs: []),
            throwsArgumentError,
          );
          expect(await _databaseState(h.db), state);
        },
      );

      if (mode == AppMode.serverSync) {
        test(
          'conserva base oficial y omite secuencia al depender de edición pendiente',
          () async {
            final target = await _create(h);
            await (h.db.update(
              h.db.events,
            )..where((e) => e.eventId.equals(target.baseEventId))).write(
              const EventsCompanion(
                deliveryStatus: Value('delivered'),
                serverSequence: Value(7),
              ),
            );
            await (h.db.update(h.db.products)
                  ..where((p) => p.id.equals(target.productId)))
                .write(const ProductsCompanion(lastServerSequence: Value(7)));
            await _assign(h, target, '001');
            expect(h.appends.last.event.baseServerSequence, 7);
            final pendingBase = h.appends.last.event.eventId;
            await _assign(h, (
              productId: target.productId,
              variantId: target.variantId,
              baseEventId: pendingBase,
            ), '002');
            expect(h.appends.last.event.baseVersion, 2);
            expect(h.appends.last.event.baseServerSequence, isNull);
            expect(
              ProductoActualizadoPayload.fromJson(
                h.appends.last.event.payload,
              ).baseEventId,
              pendingBase,
            );
          },
        );
      } else {
        test(
          'runtime y asignación standalone no resuelven servicios remotos',
          () async {
            var remoteCalls = 0;
            getIt.registerLazySingleton<SyncAvailabilityMonitor>(() {
              remoteCalls++;
              throw StateError(
                'No iniciar push, pull, preflight, health ni WebSocket.',
              );
            });
            addTearDown(() => getIt.unregister<SyncAvailabilityMonitor>());
            final config = AppConfig.initial.copyWith(
              setupCompleted: true,
              backupProvider: BackupProvider.none,
            );
            await startConfiguredRuntimeServices(config);
            final target = await _create(h);
            await _assign(h, target, '001');
            await stopConfiguredRuntimeServices(config);
            expect(remoteCalls, 0);
            expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
            expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
          },
        );
      }
    });
  }
}

CrearArticuloVarianteCommand _variant({String? name, String? barcode}) =>
    CrearArticuloVarianteCommand(
      nombre: name,
      precioVenta: '12.34',
      costoEstandar: '3.21',
      codigoBarras: barcode,
    );

Future<_Target> _create(
  ProductSupplierHarness h, {
  CrearArticuloCommand? command,
}) async {
  await h.commands.crearArticulo(
    command ??
        const CrearArticuloCommand(nombre: 'Simple', precioVenta: '12.34'),
  );
  final event = h.appends.last.event;
  final payload = ProductoCreadoPayload.fromJson(event.payload);
  return (
    productId: event.aggregateId,
    variantId: payload.variantes.first.id,
    baseEventId: event.eventId,
  );
}

Future<void> _assign(ProductSupplierHarness h, _Target target, String code) =>
    h.commands.asignarCodigoBarrasVariante(
      AsignarCodigoBarrasVarianteCommand(
        productId: target.productId,
        variantId: target.variantId,
        baseEventId: target.baseEventId,
        codigoBarras: code,
      ),
    );

String _refKey(LocalEventRef ref) =>
    '${ref.refType}:${ref.refId}:${ref.relationship}';

Future<Map<String, List<Map<String, Object?>>>> _databaseState(
  AppDatabase db,
) async => {
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

void _expectOnlyBarcodeChanged(
  ProductoActualizadoPayload payload,
  String variantId,
  String code,
) {
  final before = payload.before.toJson();
  final after = payload.after.toJson();
  final variants = after['variants'] as List;
  final selected = (variants.cast<Map<String, Object?>>()).singleWhere(
    (v) => v['variant_id'] == variantId,
  );
  expect(selected['barcode'], code);
  selected['barcode'] = payload.before.variantes
      .singleWhere((v) => v.id == variantId)
      .codigoBarras;
  // Las dependencias causales se refrescan; no son cambios de negocio.
  after['dependencies'] = before['dependencies'];
  expect(after, before);
}

Future<_Target> _complexProduct(
  ProductSupplierHarness h, {
  bool measured = false,
}) async {
  final a = await h.supplier('Proveedor A');
  final b = await h.supplier('Proveedor B');
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
  await h.tracking.inventoryCommands.crearRecurso(
    const CrearRecursoInventarioCommand(
      nombre: 'Ingrediente',
      defaultUnitId: InventoryUnitIds.piece,
      quantityDeltaAtomic: 50,
    ),
  );
  final ingredient = (await h.db.select(h.db.inventoryItems).get()).single.id;
  final target = await _create(
    h,
    command: CrearArticuloCommand.conVariantes(
      nombre: 'Producto completo',
      categoriaId: 'category',
      saleConfiguration: measured
          ? MeasuredSaleConfiguration(
              saleUnitId: InventoryUnitIds.kilogram,
              priceReferenceQuantityAtomic: 1000,
            )
          : const UnitSaleConfiguration(),
      variantes: [
        CrearArticuloVarianteCommand.conProveedores(
          nombre: 'Directa',
          precioVenta: '24.56',
          costoEstandar: '3.14',
          inventoryUnitId: measured
              ? InventoryUnitIds.kilogram
              : InventoryUnitIds.piece,
          initialStockQuantity: '4',
          proveedores: [
            ProveedorVariante(
              proveedorId: a,
              precioInformadoMenor: 1299,
              fechaInformadaMs: 1791331200000,
            ),
            ProveedorVariante(
              proveedorId: b,
              precioInformadoMenor: 0,
              fechaInformadaMs: 1791244800000,
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
          proveedores: [
            ProveedorVariante(
              proveedorId: b,
              precioInformadoMenor: 1500,
              fechaInformadaMs: 1791158400000,
            ),
          ],
        ),
        _variant(name: 'Sin seguimiento', barcode: '0077'),
        _variant(name: 'Histórica', barcode: '0066'),
      ],
    ),
  );
  final snapshot = await h.tracking.products.snapshot(target.productId);
  await (h.db.update(h.db.productVariants)
        ..where((v) => v.id.equals(snapshot.variantes.last.id)))
      .write(const ProductVariantsCompanion(active: Value(false)));
  await h.tracking.drafts.agregar(
    AgregarProductoBorradorCommand(
      variantId: snapshot.variantes[2].id,
      measuredQuantity: measured ? '0.5' : null,
      expectedUnitId: measured ? InventoryUnitIds.kilogram : null,
    ),
  );
  return target;
}
