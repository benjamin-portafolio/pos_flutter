import 'package:pos_flutter/application/edicion_masiva/cambio_explicito.dart';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/actualizar_articulo_variante_csv_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_recipe_component_command.dart';
import 'package:pos_flutter/application/commands/articulos/crear_articulo_variante_command.dart';
import 'package:pos_flutter/application/commands/inventario/crear_recurso_inventario_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_creado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';

import 'package:pos_flutter/application/import/articulo_import_preparation_service.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/data/local/import/drift_articulo_import_catalog_reader.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';

import '../../../support/product_supplier_harness.dart';

typedef _Target = ({String id, String base, ProductoCreadoPayload state});

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late ProductSupplierHarness h;
      setUp(() => h = ProductSupplierHarness(mode: mode));
      tearDown(() => h.dispose());

      for (final measured in [false, true]) {
        test('edición parcial conserva datos exactos (medido=$measured)', () async {
          final target = await _complex(h, measured: measured);
          final before = await _databaseState(h.db);
          final originalRows = await h.db.select(h.db.productVariants).get();
          final appends = h.appends.length;
          final variants = target.state.variantes;
          // Orden inverso y dos cambios: el evento conserva el orden del agregado.
          final command = _command(
            target,
            nombre: '  PRODUCTO completo  ',
            variantes: [
              ActualizarArticuloVarianteCsvCommand(
                variantId: variants[1].id,
                nombre: '  Receta nueva  ',
                precioVentaMinor: 3456,
                precioCosteMinor: 0,
                codigoBarras: ' ００１２３ ',
              ),
              ActualizarArticuloVarianteCsvCommand(
                variantId: variants[0].id,
                nombre: variants[0].nombre,
                precioVentaMinor: 3000,
                precioCosteMinor: null,
                codigoBarras: '',
              ),
            ],
          );
          expect(await h.commands.actualizarArticuloDesdeCsv(command), isTrue);
          expect(h.appends, hasLength(appends + 1));
          final event = h.appends.last.event;
          expect(event.eventType, ProductoActualizadoPayload.eventType);
          final payload = ProductoActualizadoPayload.fromJson(event.payload);
          expect(payload.baseEventId, target.base);
          expect(payload.before.toJson(), target.state.toJson());
          expect(payload.after.nombre, 'PRODUCTO completo');
          expect(payload.after.categoriaId, isNull);
          expect(
            payload.after.saleConfiguration,
            target.state.saleConfiguration,
          );
          expect(
            payload.after.variantes.map((v) => v.id),
            variants.map((v) => v.id),
          );
          expect(payload.after.variantes.map((v) => v.orden), [0, 1, 2]);
          expect(payload.after.variantes[2].toJson(), variants[2].toJson());
          expect(payload.after.variantes[0].costoEstandarMenor, isNull);
          expect(payload.after.variantes[0].codigoBarras, isNull);
          expect(payload.after.variantes[1].codigoBarras, '00123');
          expect(payload.after.variantes[1].costoEstandarMenor, 0);

          // Restaurar solamente la lista blanca debe recuperar el before exacto.
          final restored = payload.after.toJson();
          final previous = target.state.toJson();
          restored['product'] = previous['product'];
          restored['dependencies'] = previous['dependencies'];
          final restoredVariants = (restored['variants'] as List)
              .cast<Map<String, Object?>>();
          final previousVariants = (previous['variants'] as List)
              .cast<Map<String, Object?>>();
          for (var i = 0; i < 2; i++) {
            for (final field in [
              'name',
              'sale_price_minor',
              'standard_cost_minor',
              'barcode',
            ]) {
              restoredVariants[i][field] = previousVariants[i][field];
            }
          }
          expect(restored, previous);
          expect(
            ProductoActualizadoPayload.sameState(
              await h.tracking.products.snapshot(target.id),
              payload.after,
            ),
            isTrue,
          );
          final after = await _databaseState(h.db);
          for (final table in before.keys.where(
            (name) => !{
              'products',
              'product_variants',
              'events',
              'event_refs',
              'product_update_undo',
            }.contains(name),
          )) {
            expect(after[table], before[table], reason: table);
          }
          for (final row in await h.db.select(h.db.productVariants).get()) {
            final old = originalRows.singleWhere((r) => r.id == row.id);
            expect(row.createdEventId, old.createdEventId);
            expect(row.sortOrder, old.sortOrder);
            if (!old.active) expect(row, old);
          }
          final persisted = (await h.tracking.history.eventById(
            event.eventId,
          ))!;
          expect(
            persisted.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          final declared = h.appends.last.refs.map(_refKey).toSet();
          expect(declared, contains('product:${target.id}:affects'));
          expect(
            declared.where((r) => r.startsWith('inventory_item:')),
            hasLength(2),
          );
          expect(
            declared.where((r) => r.startsWith('supplier:')),
            hasLength(2),
          );
          expect(
            declared.where((r) => r.startsWith('variant_suppliers:')),
            hasLength(3),
          );
          expect(declared.any((r) => r.contains('barcode')), isFalse);
          if (measured) {
            expect(
              declared,
              contains('unit:${InventoryUnitIds.kilogram}:uses'),
            );
          }
          final refs = await h.db.select(h.db.eventRefs).get();
          expect(
            refs
                .where((r) => r.eventId == event.eventId)
                .map((r) => '${r.refType}:${r.refId}:${r.relationship}')
                .toSet(),
            mode == AppMode.standalone ? <String>{} : declared,
          );
          expect(
            payload.after.dependenciasInventario.every(
              (d) =>
                  (d.dependsOnEventId != null) == (mode == AppMode.serverSync),
            ),
            isTrue,
          );
          expect(
            payload.after.dependenciasProveedores.every(
              (d) =>
                  (d.dependsOnEventId != null) == (mode == AppMode.serverSync),
            ),
            isTrue,
          );
          expect(
            await h.db.select(h.db.productUpdateUndo).get(),
            hasLength(mode == AppMode.standalone ? 0 : 1),
          );

          // Repetir una confirmación vieja no genera otro evento ni rebasa la base.
          await expectLater(
            h.commands.actualizarArticuloDesdeCsv(command),
            throwsStateError,
          );
          expect(await _databaseState(h.db), after);
        });
      }

      test('C43 exportar, editar, reabrir, repetir y revertir en disco', () async {
        final directory = await Directory.systemTemp.createTemp('csv-reopen-');
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/isolated.sqlite');
        await h.dispose();
        h = ProductSupplierHarness(
          mode: mode,
          database: AppDatabase.forTesting(NativeDatabase(file)),
        );
        final target = await _complex(h, measured: true);
        final before = await _databaseState(h.db);
        final original = target.state;
        // Use the public CSV compositor and real DAO rows. Omit two active
        // variants; update only the direct variant, leaving its stock untouched.
        final exported = ArticuloCatalogCsv.catalogo(
          await h.db.productoDao.watchProductosListado().first,
        );
        // This controlled fixture has no commas/quotes in its fields. General
        // CSV escaping is covered by the existing parser/exporter regressions.
        final rows = exported
            .trim()
            .split('\n')
            .map((r) => r.split(','))
            .toList();
        expect(rows.every((r) => r.length == 12), isTrue);
        final header = rows.first;
        expect(header.take(2), ['product_id', 'variant_id']);
        final row = rows
            .skip(1)
            .singleWhere((r) => r[1] == original.variantes.first.id)
            .toList();
        row[3] = 'Reabierto';
        row[7] = '31.50';
        row[10] = '999';
        row[11] = '0000123';
        final csv = '${header.join(',')}\n${row.join(',')}\n';
        final csvFile = File('${directory.path}/edited.csv');
        await csvFile.writeAsString(csv, flush: true);

        ArticuloImportPreparationService preparation() =>
            ArticuloImportPreparationService(
              parser: const ArticuloImportCsv(),
              reader: DriftArticuloImportCatalogReader(h.db),
            );
        final report = await preparation().preparar(
          await csvFile.readAsString(),
        );
        expect(report.errores, isEmpty);
        expect(report.productosConCambios, hasLength(1));
        expect(
          report
              .productosConCambios
              .single
              .actual
              .cantidadReferenciaPrecioAtomic,
          250,
        );
        final result =
            await ArticuloImportBatchService(
              productoCommandService: h.commands,
              unidadInventarioRepository: UnidadInventarioRepositoryImpl(
                unitDao: h.db.unitDao,
              ),
            ).importar(
              report.productos,
              actualizaciones: report.productosConCambios,
              omitidos: report.productosSinCambios,
              onProgress: (_) {},
            );
        expect(result.productosActualizados, 1);
        expect(result.lotesFallidos, isEmpty);
        final updated = await h.tracking.products.snapshot(target.id);
        expect(updated.nombre, 'Reabierto');
        expect(updated.variantes.first.precioVentaMenor, 3150);
        expect(updated.variantes.first.codigoBarras, '0000123');
        expect(updated.saleConfiguration, original.saleConfiguration);
        expect(
          updated.variantes.first.toJson()['suppliers'],
          original.variantes.first.toJson()['suppliers'],
        );
        expect(
          updated.variantes.skip(1).map((v) => v.toJson()),
          original.variantes.skip(1).map((v) => v.toJson()),
        );
        final committed = await _databaseState(h.db);
        for (final table in before.keys.where(
          (t) => !{
            'products',
            'product_variants',
            'events',
            'event_refs',
            'product_update_undo',
          }.contains(t),
        )) {
          expect(committed[table], before[table], reason: table);
        }
        final audit = _ReopenAudit();
        Future<void> reopen() async {
          await h.dispose();
          h = ProductSupplierHarness(
            mode: mode,
            database: AppDatabase.forTesting(
              NativeDatabase(file).interceptWith(audit),
            ),
          );
        }

        await reopen();
        expect(await _databaseState(h.db), committed);
        final reloaded = await h.tracking.products.snapshot(target.id);
        expect(reloaded.toJson(), updated.toJson());
        expect(
          (await h.db.select(h.db.events).get())
              .where(
                (e) => {
                  ProductoCreadoPayload.eventType,
                  ProductoActualizadoPayload.eventType,
                }.contains(e.eventType),
              )
              .every(
                (e) =>
                    e.deliveryStatus ==
                    (mode == AppMode.standalone ? 'not_required' : 'pending'),
              ),
          isTrue,
        );
        expect(
          (await h.db.select(h.db.eventRefs).get()).isEmpty,
          mode == AppMode.standalone,
        );
        audit.reset();
        final repeated = await preparation().preparar(
          await csvFile.readAsString(),
        );
        expect(repeated.productosSinCambios, hasLength(1));
        expect(repeated.productosConCambios, isEmpty);
        final noOp =
            await ArticuloImportBatchService(
              productoCommandService: h.commands,
              unidadInventarioRepository: UnidadInventarioRepositoryImpl(
                unitDao: h.db.unitDao,
              ),
            ).importar(
              repeated.productos,
              omitidos: repeated.productosSinCambios,
              onProgress: (_) {},
            );
        expect(noOp.lotesTotales, 0);
        expect(audit.writes, 0);
        expect(audit.historyReads, 0);
        expect(await _databaseState(h.db), committed);

        // A projected update that throws must remain rolled back after reopen.
        h.failAfterProductApply = true;
        await expectLater(
          h.commands.actualizarArticuloDesdeCsv(
            ActualizarArticuloCsvCommand(
              productId: target.id,
              baseEventId: (await h.tracking.products.findProductById(
                target.id,
              ))!.lastEventId!,
              nombre: 'No debe persistir',
              categoriaId: updated.categoriaId,
              variantes: [_change(updated.variantes.first, precio: 9999)],
            ),
          ),
          throwsStateError,
        );
        expect(await _databaseState(h.db), committed);
        await reopen();
        expect(await _databaseState(h.db), committed);
      });

      test('sameState normalizado no emite, ni cambia metadatos', () async {
        final target = await _create(h);
        final before = await _databaseState(h.db);
        final count = h.appends.length;
        expect(
          await h.commands.actualizarArticuloDesdeCsv(
            _command(
              target,
              nombre: '  Ｓｉｍｐｌｅ  ',
              variantes: [
                _change(
                  target.state.variantes.first,
                  nombre: '  Ｕｎｉｃａ ',
                  codigo: ' ００１ ',
                ),
              ],
            ),
          ),
          isFalse,
        );
        expect(h.appends, hasLength(count));
        expect(await _databaseState(h.db), before);
      });

      test('asocia categoría oficial y declara su referencia', () async {
        final target = await _create(h);
        await h.db
            .into(h.db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: 'category',
                name: 'Categoría',
                sortOrder: 0,
                lastServerSequence: const Value(5),
              ),
            );
        await h.commands.actualizarArticuloDesdeCsv(
          ActualizarArticuloCsvCommand(
            productId: target.id,
            baseEventId: target.base,
            nombre: target.state.nombre,
            categoriaId: ' category ',
            variantes: [_change(target.state.variantes.first)],
          ),
        );
        final payload = ProductoActualizadoPayload.fromJson(
          h.appends.last.event.payload,
        );
        expect(payload.after.categoriaId, 'category');
        expect(payload.after.dependenciaCategoria, isNull);
        expect(
          h.appends.last.refs.map(_refKey),
          contains('category:category:uses'),
        );
        expect(
          (await h.tracking.products.snapshot(target.id)).categoriaId,
          'category',
        );
      });

      test(
        'barcode compartido no impone unicidad ni modifica la omitida',
        () async {
          final target = await _create(
            h,
            command: CrearArticuloCommand.conVariantes(
              nombre: 'Compartidos',
              variantes: [_variant('Incluida'), _variant('Omitida')],
            ),
          );
          final first = target.state.variantes.first;
          await h.commands.actualizarArticuloDesdeCsv(
            _command(
              target,
              variantes: [_change(first, precio: 1300, codigo: '001')],
            ),
          );
          final after = await h.tracking.products.snapshot(target.id);
          expect(after.variantes.map((v) => v.codigoBarras), ['001', '001']);
          expect(
            after.variantes.last.toJson(),
            target.state.variantes.last.toJson(),
          );
          expect(
            h.appends.last.refs.any((r) => r.refType.contains('barcode')),
            isFalse,
          );
        },
      );

      for (final unavailable in [
        'producto ausente',
        'producto inactivo',
        'variante ausente',
        'variante inactiva',
        'variante ajena',
        'base vacía',
        'base obsoleta',
      ]) {
        test('rechaza $unavailable dentro de la transacción', () async {
          final target = await _create(h);
          var productId = target.id;
          var variantId = target.state.variantes.first.id;
          var base = target.base;
          switch (unavailable) {
            case 'producto ausente':
              productId = 'ausente';
            case 'producto inactivo':
              await (h.db.update(h.db.products)
                    ..where((p) => p.id.equals(target.id)))
                  .write(const ProductsCompanion(active: Value(false)));
            case 'variante ausente':
              variantId = 'ausente';
            case 'variante inactiva':
              await (h.db.update(h.db.productVariants)
                    ..where((v) => v.id.equals(variantId)))
                  .write(const ProductVariantsCompanion(active: Value(false)));
            case 'variante ajena':
              variantId = (await _create(h)).state.variantes.first.id;
            case 'base vacía':
              base = '';
            case 'base obsoleta':
              await h.commands.actualizarArticuloDesdeCsv(
                _command(target, nombre: 'Edición posterior'),
              );
          }
          final before = await _databaseState(h.db);
          final count = h.appends.length;
          await expectLater(
            h.commands.actualizarArticuloDesdeCsv(
              ActualizarArticuloCsvCommand(
                productId: productId,
                baseEventId: base,
                nombre: 'Intento CSV',
                categoriaId: null,
                variantes: [
                  ActualizarArticuloVarianteCsvCommand(
                    variantId: variantId,
                    nombre: 'Única',
                    precioVentaMinor: 200,
                    precioCosteMinor: null,
                    codigoBarras: null,
                  ),
                ],
              ),
            ),
            throwsStateError,
          );
          expect(h.appends, hasLength(count));
          expect(await _databaseState(h.db), before);
        });
      }

      for (final invalid in [
        'colisión omitida',
        'variante duplicada',
        'lista vacía',
        'precio inválido',
        'barcode inválido',
      ]) {
        test('valida $invalid sobre el agregado completo', () async {
          final target = await _create(
            h,
            command: CrearArticuloCommand.conVariantes(
              nombre: 'Varias',
              variantes: [_variant('Primera'), _variant('Omitida')],
            ),
          );
          final first = target.state.variantes.first;
          final changes = switch (invalid) {
            'colisión omitida' => [_change(first, nombre: 'Ｏｍｉｔｉｄａ')],
            'variante duplicada' => [_change(first), _change(first)],
            'lista vacía' => <ActualizarArticuloVarianteCsvCommand>[],
            'precio inválido' => [_change(first, precio: 0)],
            _ => [_change(first, codigo: 'ABC')],
          };
          final before = await _databaseState(h.db);
          await expectLater(
            h.commands.actualizarArticuloDesdeCsv(
              _command(target, variantes: changes),
            ),
            throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
          );
          expect(await _databaseState(h.db), before);
        });
      }

      for (final legacy in [false, true]) {
        test(
          'conserva proveedores ${legacy ? 'desconocidos' : 'conocidos vacíos'}',
          () async {
            var target = await _create(h);
            if (legacy) {
              final payload = ProductoCreadoPayload.simple(
                nombre: 'Legado',
                categoriaId: null,
                varianteId: '00000000-0000-4000-8000-000000000001',
                precioVentaMenor: 100,
              );
              final event = h.appends.last.event.copyWith(
                eventId: 'legacy-event',
                aggregateId: 'legacy-product',
                payload: payload.toJson(),
              );
              await h.local.appendAndApply(
                event,
                refs: const [
                  LocalEventRef.affects(
                    refType: 'product',
                    refId: 'legacy-product',
                  ),
                ],
              );
              target = (
                id: event.aggregateId,
                base: event.eventId,
                state: payload,
              );
            }
            final beforeNoop = await _databaseState(h.db);
            expect(
              await h.commands.actualizarArticuloDesdeCsv(_command(target)),
              isFalse,
            );
            expect(await _databaseState(h.db), beforeNoop);
            await h.commands.actualizarArticuloDesdeCsv(
              _command(target, nombre: 'Renombrado'),
            );
            final payload = ProductoActualizadoPayload.fromJson(
              h.appends.last.event.payload,
            );
            expect(payload.before.knowsMinimumStock, !legacy);
            expect(payload.after.knowsMinimumStock, !legacy);
            expect(payload.after.variantes.first.minimumStockAtomic, isNull);
            expect(
              (await h.tracking.products.snapshot(target.id)).knowsMinimumStock,
              !legacy,
            );
            expect(
              payload.before.variantes.first.proveedores,
              legacy ? isNull : isEmpty,
            );
            expect(
              payload.after.variantes.first.proveedores,
              legacy ? isNull : isEmpty,
            );
            expect(
              (await h.tracking.products.snapshot(
                target.id,
              )).variantes.first.proveedores,
              legacy ? isNull : isEmpty,
            );
            expect(
              h.appends.last.refs.any((r) => r.refType == 'variant_suppliers'),
              !legacy,
            );
          },
        );
      }

      test('el store valida refs incluso si no las persiste', () async {
        final target = await _create(h);
        await h.commands.actualizarArticuloDesdeCsv(
          _command(target, nombre: 'Cambio'),
        );
        final before = await _databaseState(h.db);
        await expectLater(
          h.local.appendAndApply(
            h.appends.last.event.copyWith(eventId: 'sin-refs'),
            refs: [],
          ),
          throwsArgumentError,
        );
        expect(await _databaseState(h.db), before);
      });

      if (mode == AppMode.serverSync) {
        test('mantiene base oficial y dependencia de base pendiente', () async {
          final target = await _create(h);
          await (h.db.update(
            h.db.events,
          )..where((e) => e.eventId.equals(target.base))).write(
            const EventsCompanion(
              deliveryStatus: Value('delivered'),
              serverSequence: Value(7),
            ),
          );
          await (h.db.update(h.db.products)
                ..where((p) => p.id.equals(target.id)))
              .write(const ProductsCompanion(lastServerSequence: Value(7)));
          await h.commands.actualizarArticuloDesdeCsv(
            _command(target, nombre: 'Oficial'),
          );
          expect(h.appends.last.event.baseServerSequence, 7);
          final pending = h.appends.last.event.eventId;
          final current = (
            id: target.id,
            base: pending,
            state: await h.tracking.products.snapshot(target.id),
          );
          await h.commands.actualizarArticuloDesdeCsv(
            _command(current, nombre: 'Dependiente'),
          );
          expect(h.appends.last.event.baseServerSequence, isNull);
          expect(h.appends.last.event.baseVersion, 2);
          expect(
            ProductoActualizadoPayload.fromJson(
              h.appends.last.event.payload,
            ).dependencyEventIds,
            contains(pending),
          );
        });
      } else {
        test(
          'cambiar a server_sync no promueve historial standalone',
          () async {
            final target = await _create(h);
            final before = await _databaseState(h.db);
            h.tracking.config.update(
              h.tracking.config.config.copyWith(mode: AppMode.serverSync),
            );
            await expectLater(
              h.commands.actualizarArticuloDesdeCsv(
                _command(target, nombre: 'Cambio'),
              ),
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'motivo',
                  contains('importación explícita'),
                ),
              ),
            );
            expect(await _databaseState(h.db), before);
            expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
            expect(await h.db.eventDao.obtenerEventosPendientes(), isEmpty);
          },
        );
      }
    });
  }
}

CrearArticuloVarianteCommand _variant(String name) =>
    CrearArticuloVarianteCommand(
      nombre: name,
      precioVenta: '12.34',
      costoEstandar: '3.21',
      codigoBarras: '001',
    );

Future<_Target> _create(
  ProductSupplierHarness h, {
  CrearArticuloCommand? command,
}) async {
  await h.commands.crearArticulo(
    command ??
        CrearArticuloCommand.conVariantes(
          nombre: 'Simple',
          variantes: [_variant('Unica')],
        ),
  );
  final event = h.appends.last.event;
  return (
    id: event.aggregateId,
    base: event.eventId,
    state: await h.tracking.products.snapshot(event.aggregateId),
  );
}

ActualizarArticuloVarianteCsvCommand _change(
  ProductoCreadoVariante v, {
  String? nombre,
  int? precio,
  String? codigo,
}) => ActualizarArticuloVarianteCsvCommand(
  variantId: v.id,
  nombre: nombre ?? v.nombre,
  precioVentaMinor: precio ?? v.precioVentaMenor,
  precioCosteMinor: v.costoEstandarMenor,
  codigoBarras: codigo ?? v.codigoBarras,
);

ActualizarArticuloCsvCommand _command(
  _Target target, {
  String? nombre,
  List<ActualizarArticuloVarianteCsvCommand>? variantes,
}) => ActualizarArticuloCsvCommand(
  productId: target.id,
  baseEventId: target.base,
  nombre: nombre ?? target.state.nombre,
  categoriaId: null,
  variantes: variantes ?? [_change(target.state.variantes.first)],
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

Future<_Target> _complex(
  ProductSupplierHarness h, {
  required bool measured,
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
  var target = await _create(
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
          codigoBarras: '009',
          inventoryUnitId: measured
              ? InventoryUnitIds.kilogram
              : InventoryUnitIds.piece,
          initialStockQuantity: '4',
          minimumStock: CambioExplicito.establecer(measured ? '1.5' : '5'),
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
        _variant('Omitida'),
        _variant('Histórica'),
      ],
    ),
  );
  if (measured) {
    // Historical/imported valid persisted configuration: the current creation
    // command only allows the unit factor (1000), while CSV edits must retain
    // an existing reference of 250 exactly. Seed projection + original payload
    // coherently before any operation under test.
    await (h.db.update(
      h.db.products,
    )..where((p) => p.id.equals(target.id))).write(
      const ProductsCompanion(priceReferenceQuantityAtomic: Value(250)),
    );
    final event = (await h.tracking.history.eventById(target.base))!;
    final json = event.payload;
    final product = json['product'] as Map<String, Object?>;
    final sale = product['sale_configuration'] as Map<String, Object?>;
    sale['price_reference_quantity_atomic'] = 250;
    await (h.db.update(h.db.events)
          ..where((e) => e.eventId.equals(target.base)))
        .write(EventsCompanion(payload: Value(jsonEncode(json))));
  }
  await (h.db.update(h.db.productVariants)
        ..where((v) => v.id.equals(target.state.variantes.last.id)))
      .write(const ProductVariantsCompanion(active: Value(false)));
  await h.tracking.drafts.agregar(
    AgregarProductoBorradorCommand(
      variantId: target.state.variantes[2].id,
      measuredQuantity: measured ? '0.5' : null,
      expectedUnitId: measured ? InventoryUnitIds.kilogram : null,
    ),
  );
  target = (
    id: target.id,
    base: target.base,
    state: await h.tracking.products.snapshot(target.id),
  );
  return target;
}

class _ReopenAudit extends QueryInterceptor {
  int writes = 0;
  int historyReads = 0;
  void reset() {
    writes = 0;
    historyReads = 0;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) {
    if (s.contains('"events"')) historyReads++;
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
    writes += s.arguments.length;
    return super.runBatched(e, s);
  }
}
