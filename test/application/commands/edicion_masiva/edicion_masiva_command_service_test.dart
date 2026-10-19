import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_entrada_confirmada_command.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/base_revision_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_variante_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/clave_variante.dart';
import 'package:pos_flutter/application/edicion_masiva/operacion_edicion_masiva.dart';
import 'package:pos_flutter/application/sync/payloads/movimiento_inventario_registrado_payload.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_diario_edicion_masiva.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';

import '../../../support/product_supplier_harness.dart';
import '../../../support/recepcion_masiva_fixture.dart';

void main() {
  for (final mode in AppMode.values) {
    group(mode.name, () {
      late ProductSupplierHarness h;
      late EdicionMasivaCommandService service;
      setUp(() {
        h = ProductSupplierHarness(mode: mode);
        service = coordinadorRecepcion(h);
      });
      tearDown(() => h.dispose());

      test(
        'M17/M24/M31/M41/M42 catálogo único, entradas positivas e IDs originales',
        () async {
          final filas = await seedRecepcion(h);
          final before = await fotoRecepcion(h.db);
          final op = (await service.confirmar(
            batchId: 'captura',
            cambios: [
              cambioRecepcion(filas[0], venta: 3500, cantidad: 250),
              cambioRecepcion(filas[1], costo: 0, cantidad: 3),
            ],
          )).single;
          final reserved = await fotoRecepcion(h.db);
          for (final table in before.keys.where(
            (t) => t != 'bulk_edit_operations',
          )) {
            expect(reserved[table], before[table], reason: table);
          }
          expect(reserved['bulk_edit_operations'], hasLength(1));
          final result = await service.ejecutar(op);
          expect(result.eventIds, hasLength(3));
          final events = await service.eventos(result);
          expect(
            events
                .map((e) => e.eventType)
                .where((t) => t == ProductoActualizadoPayload.eventType),
            hasLength(1),
          );
          final catalog = ProductoActualizadoPayload.fromJson(
            events.first.payload,
          );
          expect(catalog.baseEventId, filas.first.baseProducto.eventId);
          expect(
            catalog.after.variantes.last.toJson(),
            catalog.before.variantes.last.toJson(),
          );
          final movements = (await h.db.select(h.db.inventoryMovements).get())
              .where((m) => result.eventIds.contains(m.eventId))
              .toList();
          expect(movements, hasLength(2));
          expect(
            movements.every(
              (m) =>
                  m.movementType == 'stock_receipt' &&
                  m.quantityDeltaAtomic > 0 &&
                  m.totalCostMinor == null,
            ),
            isTrue,
          );
          for (final entrada in result.entradas) {
            final fila = filas.singleWhere(
              (f) => f.entrada?.recurso.id == entrada.inventoryItemId,
            );
            final nuevo = await releerRecepcion(h.db, fila.clave);
            final delta = fila.nombreVariante == 'Peso' ? 250 : 3;
            expect(
              nuevo.entrada!.existenciaAtomic,
              fila.entrada!.existenciaAtomic + delta,
            );
            expect(
              nuevo.entrada!.disponibleAtomic,
              fila.entrada!.disponibleAtomic + delta,
            );
            final movement = movements.singleWhere(
              (m) => m.movementId == entrada.movementId,
            );
            expect(movement.eventId, entrada.eventId);
            final event = events.singleWhere(
              (e) => e.eventId == entrada.eventId,
            );
            final payload = MovimientoInventarioRegistradoPayload.fromJson(
              event.payload,
            );
            expect(payload.baseEventId, fila.entrada!.recurso.eventId);
            // Ninguna dependencia ficticia al evento comercial.
            expect(payload.baseEventId, isNot(result.catalogEventId));
            expect(event.baseVersion, fila.entrada!.recurso.version);
          }
          expect(
            events.every(
              (e) =>
                  e.deliveryStatus ==
                  (mode == AppMode.standalone ? 'not_required' : 'pending'),
            ),
            isTrue,
          );
          final refs = await h.db.select(h.db.eventRefs).get();
          expect(refs, mode == AppMode.standalone ? isEmpty : isNotEmpty);
          if (mode == AppMode.serverSync) {
            for (final entrada in result.entradas) {
              expect(
                refs
                    .where((r) => r.eventId == entrada.eventId)
                    .map((r) => '${r.refType}/${r.refId}'),
                unorderedEquals([
                  'inventory_item/${entrada.inventoryItemId}',
                  'inventory_movement/${entrada.movementId}',
                ]),
              );
            }
            // La entrega actual se consulta desde events, sin cambiar el diario.
            final journal = await h.db.select(h.db.bulkEditOperations).get();
            await (h.db.update(h.db.events)..where(
                  (e) => e.eventId.equals(result.entradas.first.eventId),
                ))
                .write(
                  const EventsCompanion(deliveryStatus: Value('conflict')),
                );
            expect(
              (await service.eventos(
                result,
              )).where((e) => e.deliveryStatus == 'conflict'),
              hasLength(1),
            );
            expect(
              (await h.db.select(h.db.bulkEditOperations).get()).map(
                (r) => r.toJson(),
              ),
              journal.map((r) => r.toJson()),
            );
            expect((await service.ejecutar(op)).json, result.json);
          }
        },
      );

      test(
        'M10 solo entrada conserva catálogo, memoria y proveedores',
        () async {
          final f = (await seedRecepcion(h))[1];
          final before = await fotoRecepcion(h.db);
          final op = (await service.confirmar(
            batchId: 'solo-entrada',
            cambios: [cambioRecepcion(f, cantidad: 4)],
          )).single;
          final result = await service.ejecutar(op);
          final after = await fotoRecepcion(h.db);
          expect(result.catalogEventId, isNull);
          expect(result.entradas, hasLength(1));
          for (final table in [
            'products',
            'product_variants',
            'variant_suppliers',
            'recipe_components',
            'variant_inventory_memory',
            'product_update_undo',
          ]) {
            expect(after[table], before[table], reason: table);
          }
        },
      );

      test('M25 preparación omitida no reserva ni escribe', () async {
        final f = (await seedRecepcion(h)).first;
        final before = await fotoRecepcion(h.db);
        expect(
          await service.confirmar(
            batchId: 'vacia',
            cambios: [cambioRecepcion(f)],
          ),
          isEmpty,
        );
        expect(await fotoRecepcion(h.db), before);
      });

      test(
        'M28 doble ejecución concurrente e intención en orden distinto',
        () async {
          final f = await seedRecepcion(h);
          final changes = [
            cambioRecepcion(f[0], venta: 5000, cantidad: 50),
            cambioRecepcion(f[1], costo: 100, cantidad: 2),
          ];
          final op = (await service.confirmar(
            batchId: 'doble',
            cambios: changes,
          )).single;
          expect(
            (await service.confirmar(
              batchId: 'doble',
              cambios: changes.reversed,
            )).single.intencionJson,
            op.intencionJson,
          );
          final results = await Future.wait([
            service.ejecutar(op),
            service.ejecutar(op),
          ]);
          expect(results[0].json, results[1].json);
          final applied = await fotoRecepcion(h.db);
          expect(
            (await service.ejecutar(
              OperacionEdicionMasiva.fromJson(op.intencionJson),
            )).json,
            results.first.json,
          );
          expect(await fotoRecepcion(h.db), applied);
          expect((await service.pendientes()), isEmpty);
        },
      );

      test(
        'M29 mismo ID/intención distinta se rechaza; recepción nueva tiene identidad nueva',
        () async {
          final f = (await seedRecepcion(h))[1];
          final op = (await service.confirmar(
            batchId: 'identidad',
            cambios: [cambioRecepcion(f, cantidad: 2)],
          )).single;
          await service.ejecutar(op);
          final before = await fotoRecepcion(h.db);
          final other = OperacionEdicionMasiva.confirmada(
            batchId: op.batchId,
            modo: mode,
            cambios: [cambioRecepcion(f, cantidad: 3)],
          );
          expect(other.operationId, op.operationId);
          await expectLater(service.ejecutar(other), throwsStateError);
          await expectLater(
            service.confirmar(batchId: op.batchId, cambios: other.cambios),
            throwsStateError,
          );
          expect(await fotoRecepcion(h.db), before);
          final fresh = await releerRecepcion(h.db, f.clave);
          final nueva = (await service.confirmar(
            batchId: 'recepción-nueva',
            cambios: [cambioRecepcion(fresh, cantidad: 2)],
          )).single;
          expect(nueva.operationId, isNot(op.operationId));
          await service.ejecutar(nueva);
          expect(
            (await releerRecepcion(h.db, f.clave)).entrada!.existenciaAtomic,
            f.entrada!.existenciaAtomic + 4,
          );
        },
      );

      for (final fase in ['catalogo', 'movimiento', 'resultado']) {
        test('M26 rollback completo tras $fase en SQLite real', () async {
          final f = await seedRecepcion(h);
          final op = (await service.confirmar(
            batchId: fase,
            cambios: [
              cambioRecepcion(f[0], venta: 4100, cantidad: 250),
              cambioRecepcion(f[1], costo: 300, cantidad: 5),
            ],
          )).single;
          final before = await fotoRecepcion(h.db);
          final trigger = switch (fase) {
            'catalogo' =>
              "BEFORE INSERT ON inventory_movements WHEN NEW.movement_type = 'stock_receipt'",
            'movimiento' =>
              "BEFORE INSERT ON inventory_movements WHEN NEW.movement_type = 'stock_receipt' AND (SELECT count(*) FROM inventory_movements WHERE movement_type='stock_receipt') = 1",
            _ =>
              "BEFORE UPDATE OF result_json ON bulk_edit_operations WHEN NEW.result_json IS NOT NULL",
          };
          await h.db.customStatement(
            "CREATE TRIGGER fail_receipt $trigger BEGIN SELECT RAISE(ABORT, 'fallo inyectado $fase'); END",
          );
          await expectLater(service.ejecutar(op), throwsA(isA<Exception>()));
          expect(await fotoRecepcion(h.db), before);
          await h.db.customStatement('DROP TRIGGER fail_receipt');
          final result = await service.ejecutar(op);
          expect(result.entradas, hasLength(2));
          expect((await service.ejecutar(op)).json, result.json);
        });
      }

      test(
        'M27 segundo producto falla; primero/tercero confirman y no se repiten',
        () async {
          final a = (await seedRecepcion(h, nombre: 'A'))[1];
          final b = (await seedRecepcion(h, nombre: 'B'))[1];
          final c = (await seedRecepcion(h, nombre: 'C'))[1];
          await service.confirmar(
            batchId: 'tres',
            cambios: [
              for (final f in [a, b, c])
                cambioRecepcion(f, venta: 6000, cantidad: 2),
            ],
          );
          await h.db.customStatement(
            "CREATE TRIGGER fail_second BEFORE INSERT ON inventory_movements WHEN NEW.inventory_item_id = '${b.entrada!.recurso.id}' AND NEW.movement_type = 'stock_receipt' BEGIN SELECT RAISE(ABORT, 'segundo producto'); END",
          );
          final results = await service.continuar('tres');
          expect(results.map((r) => r.error != null), [false, true, false]);
          expect(
            (await releerRecepcion(h.db, b.clave)).ventaMinor,
            b.ventaMinor,
          );
          expect(
            (await releerRecepcion(h.db, b.clave)).entrada!.existenciaAtomic,
            b.entrada!.existenciaAtomic,
          );
          final aState = await releerRecepcion(h.db, a.clave);
          final cState = await releerRecepcion(h.db, c.clave);
          await h.db.customStatement('DROP TRIGGER fail_second');
          final retry = await service.continuar('tres');
          expect(retry.every((r) => r.error == null), isTrue);
          expect(retry.first.resultado!.json, results.first.resultado!.json);
          expect(retry.last.resultado!.json, results.last.resultado!.json);
          expect(
            (await releerRecepcion(h.db, a.clave)).entrada!.existenciaAtomic,
            aState.entrada!.existenciaAtomic,
          );
          expect(
            (await releerRecepcion(h.db, c.clave)).entrada!.existenciaAtomic,
            cState.entrada!.existenciaAtomic,
          );
        },
      );

      for (final cambio in [
        'product-base',
        'product-active',
        'variant-active',
        'missing',
        'ownership',
        'link',
        'recipe',
        'resource-active',
        'resource-base',
        'resource-unit',
        'unit-active',
        'unit-factor',
        'unit-digits',
        'balance-version',
        'balance-event',
        'balance-amount',
      ]) {
        test('M19–M22 rechaza $cambio sin rebasar ni escribir', () async {
          final f = (await seedRecepcion(h))[1];
          var captured = cambioRecepcion(f, venta: 9000, cantidad: 3);
          if (cambio == 'missing' || cambio == 'ownership') {
            captured = CambioVarianteMasiva(
              clave: ClaveVariante(
                f.clave.productId,
                cambio == 'missing'
                    ? 'inexistente'
                    : (await seedRecepcion(
                        h,
                        nombre: 'Otro',
                      ))[0].clave.variantId,
              ),
              baseProducto: f.baseProducto,
              venta: captured.venta,
              costo: captured.costo,
              precioProveedor: null,
              entrada: captured.entrada,
            );
          }
          final op = (await service.confirmar(
            batchId: cambio,
            cambios: [captured],
          )).single;
          final p = f.clave.productId;
          final v = f.clave.variantId;
          final i = f.entrada!.recurso.id;
          final sql = switch (cambio) {
            'product-base' =>
              "UPDATE products SET version=version+1,last_event_id='nuevo' WHERE id='$p'",
            'product-active' => "UPDATE products SET active=0 WHERE id='$p'",
            'variant-active' =>
              "UPDATE product_variants SET active=0 WHERE id='$v'",
            'link' =>
              "UPDATE product_variants SET inventory_item_id=NULL WHERE id='$v'",
            'recipe' =>
              "INSERT INTO recipe_components(variant_id,inventory_item_id,quantity_atomic) VALUES('$v','$i',1)",
            'resource-active' =>
              "UPDATE inventory_items SET active=0 WHERE id='$i'",
            'resource-base' =>
              "UPDATE inventory_items SET version=version+1,last_event_id='nuevo' WHERE id='$i'",
            'resource-unit' =>
              "UPDATE inventory_items SET default_unit_id='${InventoryUnitIds.kilogram}' WHERE id='$i'",
            'unit-active' =>
              "UPDATE units SET active=0 WHERE unit_id='${f.entrada!.unidad.id}'",
            'unit-factor' =>
              "UPDATE units SET atomic_factor=10 WHERE unit_id='${f.entrada!.unidad.id}'",
            'unit-digits' =>
              "UPDATE units SET max_fraction_digits=1 WHERE unit_id='${f.entrada!.unidad.id}'",
            'balance-version' =>
              "UPDATE inventory_balances SET version=version+1 WHERE inventory_item_id='$i'",
            'balance-event' =>
              "UPDATE inventory_balances SET last_event_id='nuevo' WHERE inventory_item_id='$i'",
            'balance-amount' =>
              "UPDATE inventory_balances SET quantity_on_hand_atomic=quantity_on_hand_atomic+1 WHERE inventory_item_id='$i'",
            _ => 'SELECT 1',
          };
          if (sql != 'SELECT 1') await h.db.customStatement(sql);
          final before = await fotoRecepcion(h.db);
          await expectLater(service.ejecutar(op), throwsStateError);
          expect(await fotoRecepcion(h.db), before);
          expect(
            (await service.pendientes()).single.operacion.intencionJson,
            op.intencionJson,
          );
        });
      }

      test(
        'M22 saldo que vuelve al mismo valor no acredita idempotencia ni base',
        () async {
          final f = (await seedRecepcion(h))[1];
          final op = (await service.confirmar(
            batchId: 'saldo-igual',
            cambios: [cambioRecepcion(f, cantidad: 2)],
          )).single;
          for (final delta in [1, -1]) {
            await h.tracking.inventoryCommands.registrarMovimiento(
              RegistrarMovimientoInventarioCommand(
                inventoryItemId: f.entrada!.recurso.id,
                movementType: TipoMovimientoInventario.manualAdjustment,
                quantityDeltaAtomic: delta,
                movementReason: 'Concurrente',
              ),
            );
          }
          expect(
            (await releerRecepcion(h.db, f.clave)).entrada!.existenciaAtomic,
            f.entrada!.existenciaAtomic,
          );
          await expectLater(service.ejecutar(op), throwsStateError);
        },
      );

      test(
        'M32 pendientes en otro modo bloqueados; cerrar explícitamente conserva aplicados',
        () async {
          final a = (await seedRecepcion(h, nombre: 'A'))[1];
          final b = (await seedRecepcion(h, nombre: 'B'))[1];
          final ops = await service.confirmar(
            batchId: 'modo',
            cambios: [
              cambioRecepcion(a, cantidad: 2),
              cambioRecepcion(b, cantidad: 2),
            ],
          );
          final applied = await service.ejecutar(ops.first);
          h.tracking.config.update(
            h.tracking.config.config.copyWith(
              mode: mode == AppMode.standalone
                  ? AppMode.serverSync
                  : AppMode.standalone,
            ),
          );
          final before = await fotoRecepcion(h.db);
          await expectLater(service.ejecutar(ops.last), throwsStateError);
          expect((await service.ejecutar(ops.first)).json, applied.json);
          expect(await fotoRecepcion(h.db), before);
          await service.cerrarPendientes('modo');
          expect(await service.pendientes(), isEmpty);
          await expectLater(service.ejecutar(ops.last), throwsStateError);
          expect((await service.ejecutar(ops.first)).json, applied.json);
          final rows = await h.db.select(h.db.bulkEditOperations).get();
          expect(rows.map((r) => r.localState), ['aplicada', 'cerrada']);
        },
      );

      test(
        'M34 revisión obsoleta se cierra y vuelve a confirmar con identidad nueva',
        () async {
          final f = (await seedRecepcion(h))[1];
          final op = (await service.confirmar(
            batchId: 'obsoleta',
            cambios: [cambioRecepcion(f, cantidad: 2)],
          )).single;
          await h.tracking.inventoryCommands.registrarMovimiento(
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: f.entrada!.recurso.id,
              movementType: TipoMovimientoInventario.stockReceipt,
              quantityDeltaAtomic: 1,
            ),
          );
          await expectLater(service.ejecutar(op), throwsStateError);
          await service.cerrarPendientes(op.batchId);
          final newOp = (await service.confirmar(
            batchId: 'revisada',
            cambios: [
              cambioRecepcion(
                await releerRecepcion(h.db, f.clave),
                cantidad: 2,
              ),
            ],
          )).single;
          await expectLater(service.ejecutar(op), throwsStateError);
          await service.ejecutar(newOp);
          expect(
            (await releerRecepcion(h.db, f.clave)).entrada!.existenciaAtomic,
            f.entrada!.existenciaAtomic + 3,
          );
        },
      );

      test(
        'comando estricto rechaza base vieja; consumidor anterior conserva base viva',
        () async {
          final f = (await seedRecepcion(h))[1];
          final diario = DriftDiarioEdicionMasiva(
            db: h.db,
            config: h.tracking.config,
            context: h.tracking.context,
          );
          final command = RegistrarEntradaConfirmadaCommand(
            base: f.entrada!,
            cantidadAtomic: 1,
          );
          await diario.transaccion(
            (u) => u.inventario.registrarEntradaConfirmada(command),
          );
          final before = await fotoRecepcion(h.db);
          await expectLater(
            diario.transaccion(
              (u) => u.inventario.registrarEntradaConfirmada(command),
            ),
            throwsStateError,
          );
          expect(await fotoRecepcion(h.db), before);
          await h.tracking.inventoryCommands.registrarMovimiento(
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: f.entrada!.recurso.id,
              movementType: TipoMovimientoInventario.stockReceipt,
              quantityDeltaAtomic: 2,
            ),
          );
          expect(
            (await releerRecepcion(h.db, f.clave)).entrada!.existenciaAtomic,
            f.entrada!.existenciaAtomic + 3,
          );
        },
      );

      test(
        'M06 límites positivos y saldo previsto revierten también catálogo',
        () async {
          final f = (await seedRecepcion(h))[1];
          final op = (await service.confirmar(
            batchId: 'rango',
            cambios: [
              cambioRecepcion(f, venta: 9000, cantidad: 9007199254740991),
            ],
          )).single;
          final before = await fotoRecepcion(h.db);
          await expectLater(service.ejecutar(op), throwsFormatException);
          expect(await fotoRecepcion(h.db), before);
          final diario = DriftDiarioEdicionMasiva(
            db: h.db,
            config: h.tracking.config,
            context: h.tracking.context,
          );
          for (final cantidad in [0, -1, 9007199254740992]) {
            await expectLater(
              diario.transaccion(
                (u) => u.inventario.registrarEntradaConfirmada(
                  RegistrarEntradaConfirmadaCommand(
                    base: f.entrada!,
                    cantidadAtomic: cantidad,
                  ),
                ),
              ),
              throwsFormatException,
            );
          }
        },
      );

      test(
        'M16/M17 medido conserva referencia comercial y entrada en unidad del recurso',
        () async {
          final f = (await seedRecepcion(h, medido: true))[0];
          expect(f.unidadVenta!.id, InventoryUnitIds.gram);
          expect(f.entrada!.unidad.id, InventoryUnitIds.kilogram);
          final op = (await service.confirmar(
            batchId: 'medido',
            cambios: [cambioRecepcion(f, venta: 4500, costo: 0, cantidad: 250)],
          )).single;
          expect(
            OperacionEdicionMasiva.fromJson(op.intencionJson).intencionJson,
            op.intencionJson,
          );
          final result = await service.ejecutar(op);
          final after = await releerRecepcion(h.db, f.clave);
          expect(after.configuracionVenta, f.configuracionVenta);
          expect(after.entrada!.existenciaAtomic, 750);
          expect(after.ventaMinor, 4500);
          expect(after.costoMinor, 0);
          expect(result.entradas, hasLength(1));
        },
      );

      test(
        'M06 magnitud no representable en unidad confirmada revierte producto',
        () async {
          final original = (await seedRecepcion(h))[1];
          await h.db.customStatement(
            "UPDATE units SET atomic_factor=3,max_fraction_digits=1 WHERE unit_id='${original.entrada!.unidad.id}'",
          );
          final f = await releerRecepcion(h.db, original.clave);
          final op = (await service.confirmar(
            batchId: 'atomos',
            cambios: [cambioRecepcion(f, venta: 8000, cantidad: 1)],
          )).single;
          final before = await fotoRecepcion(h.db);
          await expectLater(service.ejecutar(op), throwsStateError);
          expect(await fotoRecepcion(h.db), before);
        },
      );

      test(
        'sin capacidad de transacción/historial no hay fallback de entrada estricta',
        () async {
          final f = (await seedRecepcion(h))[1];
          final before = await fotoRecepcion(h.db);
          expect(
            () => h.tracking.inventoryCommands.registrarEntradaConfirmada(
              RegistrarEntradaConfirmadaCommand(
                base: f.entrada!,
                cantidadAtomic: 1,
              ),
            ),
            throwsStateError,
          );
          expect(await fotoRecepcion(h.db), before);
        },
      );

      if (mode == AppMode.serverSync) {
        test(
          'M20/M21 eco de las mismas bases acredita secuencia sin rebasar',
          () async {
            final f = (await seedRecepcion(h))[1];
            final op = (await service.confirmar(
              batchId: 'eco',
              cambios: [cambioRecepcion(f, venta: 8000, cantidad: 2)],
            )).single;
            await h.db.customStatement(
              "UPDATE products SET last_server_sequence=20 WHERE id='${f.clave.productId}'",
            );
            await h.db.customStatement(
              "UPDATE inventory_items SET last_server_sequence=10 WHERE id='${f.entrada!.recurso.id}'",
            );
            await h.db.customStatement(
              "UPDATE inventory_balances SET last_server_sequence=10 WHERE inventory_item_id='${f.entrada!.recurso.id}'",
            );
            await (h.db.update(
              h.db.events,
            )..where((e) => e.eventId.equals(f.baseProducto.eventId!))).write(
              const EventsCompanion(
                deliveryStatus: Value('delivered'),
                serverSequence: Value(20),
              ),
            );
            await (h.db.update(h.db.events)
                  ..where((e) => e.eventId.equals(f.entrada!.recurso.eventId!)))
                .write(
                  const EventsCompanion(
                    deliveryStatus: Value('delivered'),
                    serverSequence: Value(10),
                  ),
                );
            final result = await service.ejecutar(op);
            final events = await service.eventos(result);
            expect(events.first.baseServerSequence, 20);
            expect(events.last.baseServerSequence, 10);
            expect(
              ProductoActualizadoPayload.fromJson(
                events.first.payload,
              ).baseEventId,
              f.baseProducto.eventId,
            );
            expect(
              MovimientoInventarioRegistradoPayload.fromJson(
                events.last.payload,
              ).baseEventId,
              f.entrada!.recurso.eventId,
            );
          },
        );
      }
      if (mode == AppMode.standalone) {
        for (final historial in ['producto', 'recurso']) {
          test(
            'M42 historial standalone de $historial no se promueve al reservar en server_sync',
            () async {
              final f = (await seedRecepcion(h))[1];
              h.tracking.config.update(
                h.tracking.config.config.copyWith(mode: AppMode.serverSync),
              );
              if (historial == 'recurso') {
                await (h.db.update(h.db.events)
                      ..where((e) => e.eventId.equals(f.baseProducto.eventId!)))
                    .write(
                      const EventsCompanion(deliveryStatus: Value('pending')),
                    );
              }
              final op = (await service.confirmar(
                batchId: 'sin-importar-$historial',
                cambios: [cambioRecepcion(f, cantidad: 2)],
              )).single;
              final before = await fotoRecepcion(h.db);
              await expectLater(service.ejecutar(op), throwsStateError);
              expect(await fotoRecepcion(h.db), before);
              expect(await h.db.select(h.db.eventRefs).get(), isEmpty);
            },
          );
        }
      }

      test(
        'M19 duplicados y bases dispares rechazan reserva completa',
        () async {
          final f = await seedRecepcion(h);
          final before = await fotoRecepcion(h.db);
          await expectLater(
            service.confirmar(
              batchId: 'dup',
              cambios: [
                cambioRecepcion(f[0], cantidad: 1),
                cambioRecepcion(f[0], cantidad: 2),
              ],
            ),
            throwsFormatException,
          );
          final c = cambioRecepcion(f[1], cantidad: 1);
          final mismatch = CambioVarianteMasiva(
            clave: c.clave,
            baseProducto: BaseRevisionMasiva(
              id: c.clave.productId,
              version: c.baseProducto.version + 1,
              eventId: 'otro',
              serverSequence: null,
            ),
            venta: c.venta,
            costo: c.costo,
            precioProveedor: null,
            entrada: c.entrada,
          );
          await expectLater(
            service.confirmar(
              batchId: 'bases',
              cambios: [cambioRecepcion(f[0], cantidad: 1), mismatch],
            ),
            throwsFormatException,
          );
          expect(await fotoRecepcion(h.db), before);
        },
      );
    });
  }
}
