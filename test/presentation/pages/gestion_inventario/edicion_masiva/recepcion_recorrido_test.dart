import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/application/edicion_masiva/operacion_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/registro_operacion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/resultado_operacion_masiva.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/borrador_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/controlador_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/resultado_guardado_masivo.dart';

import '../../../../support/product_supplier_harness.dart';
import '../../../../support/recepcion_masiva_fixture.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  for (final modo in AppMode.values) {
    group('Recorrido con SQLite real ${modo.name}', () {
      late ProductSupplierHarness h;
      final controladores = <ControladorEdicionMasiva>[];
      setUp(() => h = ProductSupplierHarness(mode: modo));
      tearDown(() async {
        for (final c in controladores) {
          c.dispose();
        }
        controladores.clear();
        await h.dispose();
      });
      ControladorEdicionMasiva crear({EdicionMasivaCommandService? comando}) {
        final c = ControladorEdicionMasiva(
          catalogo: DriftCatalogoEdicionMasiva(h.db),
          comando: comando ?? coordinadorRecepcion(h),
          ahora: () => DateTime.utc(2026, 10, 18),
        );
        controladores.add(c);
        return c;
      }

      test(
        'M03/M09/M11/M12/M16: dos vistas, proveedor, cantidades sustituidas y venta independiente',
        () async {
          final filas = await seedRecepcion(h, medido: true);
          final f = filas[1];
          final otro = filas[0];
          final a = await h.supplier('A');
          final b = await h.supplier('B');
          final c = crear();
          c.elegirProveedorGlobal(a);
          await c.editarCosto(f.clave, '11');
          c.elegirProveedorGlobal(b);
          c.cambiarVista(VistaEdicionMasiva.recepcionCompacta);
          await c.editarCantidad(f.clave, '1.25');
          await c.editarCantidad(f.clave, '2.5');
          await c.editarVenta(otro.clave, '35');
          expect(c.captura(f.clave)!.proveedorId, a);
          expect(c.captura(f.clave)!.venta, isNull);
          final soloVenta = await c.prepararRevision();
          expect(
            soloVenta.cambios
                .singleWhere((e) => e.clave == otro.clave)
                .precioProveedor,
            isNull,
          );
          await c.editarProveedorFila(
            f.clave,
            b,
            fecha: DateTime.utc(2026, 10, 17),
          );
          await c.cambiarBusqueda('no existe');
          c.cambiarSoloCambios(true);
          final revision = await c.prepararRevision();
          expect(revision.cambios, hasLength(2));
          final cambio = revision.cambios.singleWhere(
            (e) => e.clave == f.clave,
          );
          expect(cambio.entrada!.cantidadAtomic, 2500);
          expect(cambio.entrada!.base.unidad.simbolo, 'kg');
          expect(cambio.precioProveedor!.proveedorId, b);
          expect(cambio.venta.establecer, isFalse);
          final r = await c.guardar(revision);
          expect(r.single.aplicada, isTrue);
          final actual = await releerRecepcion(h.db, f.clave);
          expect(actual.ventaMinor, 2000);
          expect(actual.costoMinor, 1100);
          expect(actual.entrada!.existenciaAtomic, 7500);
          expect(actual.proveedores.single.proveedorId, b);
          expect(
            actual.proveedores.single.fechaInformadaMs,
            DateTime.utc(2026, 10, 17).millisecondsSinceEpoch,
          );
          expect(
            (await releerRecepcion(h.db, otro.clave)).proveedores,
            isEmpty,
          );
          final foto = await fotoRecepcion(h.db);
          expect(await c.guardar(revision), same(r));
          expect(await fotoRecepcion(h.db), foto);
        },
      );

      test(
        'M40: avance después del commit, doble confirmación y cancelación esperan al producto activo',
        () async {
          final a = (await seedRecepcion(h, nombre: 'A'))[1];
          final b = (await seedRecepcion(h, nombre: 'B'))[1];
          final lento = _RespuestaRetenida(coordinadorRecepcion(h));
          final c = crear(comando: lento);
          await c.editarCantidad(a.clave, '2');
          await c.editarCantidad(b.clave, '3');
          final revision = await c.prepararRevision();
          final guardado = c.guardar(revision);
          await lento.commit.future;
          expect(c.guardando, isTrue);
          expect(c.productosGuardados, 0);
          expect(
            (await releerRecepcion(h.db, a.clave)).entrada!.existenciaAtomic,
            7,
          );
          await expectLater(c.guardar(revision), throwsStateError);
          c.cancelarGuardado();
          expect(c.guardando, isTrue);
          lento.responder.complete();
          final resultados = await guardado;
          expect(resultados.map((r) => r.estado), [
            EstadoGuardadoMasivo.aplicada,
            EstadoGuardadoMasivo.pendiente,
          ]);
          expect(c.guardando, isFalse);
          expect(
            (await releerRecepcion(h.db, b.clave)).entrada!.existenciaAtomic,
            5,
          );
          expect(await c.comando.pendientes(), hasLength(1));
          expect(c.captura(a.clave), isNull);
          expect(c.captura(b.clave)!.cantidad, '3');
          final recuperado = crear();
          final foto = await fotoRecepcion(h.db);
          final registros = await recuperado.registros();
          expect(await fotoRecepcion(h.db), foto, reason: 'Abrir no ejecuta');
          final batch = registros.first.operacion.batchId;
          final r = await recuperado.continuarCaptura(batch);
          expect(r.every((r) => r.aplicada), isTrue);
          expect(
            (await releerRecepcion(h.db, a.clave)).entrada!.existenciaAtomic,
            7,
          );
          expect(
            (await releerRecepcion(h.db, b.clave)).entrada!.existenciaAtomic,
            8,
          );
          final finalizada = await fotoRecepcion(h.db);
          await recuperado.continuarCaptura(batch);
          expect(await fotoRecepcion(h.db), finalizada);
        },
      );

      test(
        'M34/M40: rollback real del segundo producto, tercero aplicado y reintento sin repetir éxitos',
        () async {
          final a = (await seedRecepcion(h, nombre: 'A'))[1];
          final b = (await seedRecepcion(h, nombre: 'B'))[1];
          final d = (await seedRecepcion(h, nombre: 'C'))[1];
          final c = crear();
          for (final f in [a, b, d]) {
            await c.editarCosto(f.clave, '15');
            await c.editarCantidad(f.clave, '2');
          }
          await h.db.customStatement(
            "CREATE TRIGGER fail_second BEFORE INSERT ON inventory_movements WHEN NEW.inventory_item_id = '${b.entrada!.recurso.id}' AND NEW.movement_type = 'stock_receipt' BEGIN SELECT RAISE(ABORT, 'segundo producto'); END",
          );
          final resultados = await c.guardar(await c.prepararRevision());
          expect(resultados.map((r) => r.estado), [
            EstadoGuardadoMasivo.aplicada,
            EstadoGuardadoMasivo.fallida,
            EstadoGuardadoMasivo.aplicada,
          ]);
          final sinAplicar = await releerRecepcion(h.db, b.clave);
          expect(sinAplicar.costoMinor, 1000);
          expect(sinAplicar.entrada!.existenciaAtomic, 5);
          expect(c.borrador.filas.keys, [b.clave]);
          await h.db.customStatement('DROP TRIGGER fail_second');
          await c.guardar(await c.prepararRevision());
          for (final f in [a, b, d]) {
            final actual = await releerRecepcion(h.db, f.clave);
            expect(actual.costoMinor, 1500);
            expect(actual.entrada!.existenciaAtomic, 7);
          }
          expect(await c.comando.pendientes(), isEmpty);
        },
      );

      test(
        'M22/M34/M37: saldo obsoleto conserva captura, nueva revisión explícita cierra solo pendientes',
        () async {
          final a = (await seedRecepcion(h, nombre: 'A'))[1];
          final b = (await seedRecepcion(h, nombre: 'B'))[1];
          final comando = coordinadorRecepcion(h);
          final ops = await comando.confirmar(
            batchId: 'revisar',
            cambios: [
              cambioRecepcion(a, cantidad: 2),
              cambioRecepcion(b, costo: 1200, cantidad: 3),
            ],
          );
          await comando.ejecutar(ops.first);
          await h.tracking.inventoryCommands.registrarMovimiento(
            // El cambio de saldo se produce por el mismo flujo real de eventos.
            RegistrarMovimientoInventarioCommand(
              inventoryItemId: b.entrada!.recurso.id,
              movementType: TipoMovimientoInventario.stockReceipt,
              quantityDeltaAtomic: 1,
            ),
          );
          final c = crear();
          await c.recuperarParaRevision('revisar');
          final revision = await c.prepararRevision();
          expect(revision.tieneErrores, isTrue);
          expect(c.borrador.filas.keys, [b.clave]);
          expect(c.captura(b.clave)!.cantidad, '3');
          await expectLater(c.guardar(revision), throwsStateError);
          await c.revisarEstadoNuevo();
          final nueva = await c.prepararRevision();
          expect(nueva.tieneErrores, isFalse);
          expect(nueva.cambios.single.entrada!.existenciaPrevistaAtomic, 9);
          final registros = await comando.registros(batchId: 'revisar');
          expect(registros.map((r) => r.estado).toSet(), {
            EstadoOperacionMasiva.aplicada,
            EstadoOperacionMasiva.cerrada,
          });
          await c.guardar(nueva);
          expect(
            (await releerRecepcion(h.db, a.clave)).entrada!.existenciaAtomic,
            7,
          );
          expect(
            (await releerRecepcion(h.db, b.clave)).entrada!.existenciaAtomic,
            9,
          );
          expect(c.captura(b.clave), isNull);
        },
      );

      test(
        'M34: editar una pendiente requiere nueva identidad explícita y conserva aplicados',
        () async {
          final a = (await seedRecepcion(h, nombre: 'A'))[1];
          final b = (await seedRecepcion(h, nombre: 'B'))[1];
          final core = coordinadorRecepcion(h);
          final ops = await core.confirmar(
            batchId: 'original',
            cambios: [
              cambioRecepcion(a, cantidad: 2),
              cambioRecepcion(b, cantidad: 3),
            ],
          );
          await core.ejecutar(ops.first);
          final c = crear();
          await c.recuperarParaRevision('original');
          await c.editarCantidad(b.clave, '4');
          final antes = await fotoRecepcion(h.db);
          await expectLater(
            c.guardar(await c.prepararRevision()),
            throwsStateError,
          );
          expect(await fotoRecepcion(h.db), antes);
          expect(c.captura(b.clave)!.cantidad, '4');
          await c.revisarEstadoNuevo();
          final r = await c.guardar(await c.prepararRevision());
          expect(r.single.resultado!.operationId, isNot(ops.last.operationId));
          expect(
            (await releerRecepcion(h.db, a.clave)).entrada!.existenciaAtomic,
            7,
          );
          expect(
            (await releerRecepcion(h.db, b.clave)).entrada!.existenciaAtomic,
            9,
          );
          final registros = await core.registros(batchId: 'original');
          expect(registros.last.estado, EstadoOperacionMasiva.cerrada);
          final resultados = await crear().continuarCaptura('original');
          expect(resultados.map((r) => r.estado), [
            EstadoGuardadoMasivo.aplicada,
            EstadoGuardadoMasivo.omitida,
          ]);
        },
      );

      test(
        'M32/M34: recuperar o cambiar bases en otro modo no promueve historial',
        () async {
          final f = (await seedRecepcion(h))[1];
          final core = coordinadorRecepcion(h);
          await core.confirmar(
            batchId: 'modo',
            cambios: [cambioRecepcion(f, cantidad: 2)],
          );
          final c = crear();
          await c.recuperarParaRevision('modo');
          h.tracking.config.update(
            h.tracking.config.config.copyWith(
              mode: modo == AppMode.standalone
                  ? AppMode.serverSync
                  : AppMode.standalone,
            ),
          );
          final antes = await fotoRecepcion(h.db);
          await expectLater(
            crear().recuperarParaRevision('modo'),
            throwsStateError,
          );
          await expectLater(c.revisarEstadoNuevo(), throwsStateError);
          expect(c.captura(f.clave)!.cantidad, '2');
          expect(await fotoRecepcion(h.db), antes);
        },
      );

      test(
        'M34: continuar no descarta capturas nuevas de un producto pendiente',
        () async {
          final filas = await seedRecepcion(h);
          final f = filas[1];
          final c = crear();
          await c.comando.confirmar(
            batchId: 'no-sustituir',
            cambios: [cambioRecepcion(f, cantidad: 2)],
          );
          await c.editarVenta(filas[0].clave, '38');
          final antes = await fotoRecepcion(h.db);
          await expectLater(
            c.continuarCaptura('no-sustituir'),
            throwsStateError,
          );
          expect(c.captura(filas[0].clave)!.venta, '38');
          await expectLater(
            c.guardar(await c.prepararRevision()),
            throwsStateError,
          );
          expect(await fotoRecepcion(h.db), antes);
        },
      );

      test(
        'M16/M21/M34: revisar bases no convierte una entrada a otra unidad',
        () async {
          final f = (await seedRecepcion(h, medido: true))[1];
          final c = crear();
          await c.editarCantidad(f.clave, '2.5');
          final base = c.captura(f.clave)!.original.entrada!;
          await h.db.customStatement(
            'UPDATE inventory_items SET default_unit_id = ? WHERE id = ?',
            [InventoryUnitIds.gram, base.recurso.id],
          );
          final antes = await fotoRecepcion(h.db);
          expect((await c.prepararRevision()).tieneErrores, isTrue);
          await expectLater(c.revisarEstadoNuevo(), throwsStateError);
          expect(c.captura(f.clave)!.cantidad, '2.5');
          expect(
            c.captura(f.clave)!.original.entrada!.unidad.id,
            base.unidad.id,
          );
          expect(await fotoRecepcion(h.db), antes);
        },
      );

      test(
        'M25/M40: productos sin diferencias se informan omitidos sin reservar ni escribir',
        () async {
          final f = (await seedRecepcion(h))[1];
          final c = crear();
          await c.editarVenta(f.clave, '20,00');
          final antes = await fotoRecepcion(h.db);
          final r = await c.guardar(await c.prepararRevision());
          expect(r.single.estado, EstadoGuardadoMasivo.omitida);
          expect(await fotoRecepcion(h.db), antes);
        },
      );
    });
  }

  test(
    'M34: cerrar/reabrir SQLite recupera confirmados y aplicados sin ejecución automática',
    () async {
      final directorio = await Directory.systemTemp.createTemp('pos-s5-');
      addTearDown(() => directorio.delete(recursive: true));
      final archivo = File('${directorio.path}/captura.sqlite');
      var h = ProductSupplierHarness(
        database: AppDatabase.forTesting(NativeDatabase(archivo)),
      );
      final a = (await seedRecepcion(h, nombre: 'A'))[1];
      final b = (await seedRecepcion(h, nombre: 'B'))[1];
      final comando = coordinadorRecepcion(h);
      final ops = await comando.confirmar(
        batchId: 'persistida',
        cambios: [
          cambioRecepcion(a, cantidad: 2),
          cambioRecepcion(b, cantidad: 3),
        ],
      );
      final aplicado = await comando.ejecutar(ops.first);
      await h.dispose();
      h = ProductSupplierHarness(
        database: AppDatabase.forTesting(NativeDatabase(archivo)),
      );
      addTearDown(() => h.dispose());
      final c = ControladorEdicionMasiva(
        catalogo: DriftCatalogoEdicionMasiva(h.db),
        comando: coordinadorRecepcion(h),
      );
      addTearDown(c.dispose);
      final antes = await fotoRecepcion(h.db);
      expect(await c.registros(), hasLength(2));
      expect(await fotoRecepcion(h.db), antes);
      final resultados = await c.continuarCaptura('persistida');
      expect(resultados.first.resultado!.json, aplicado.json);
      expect(
        (await releerRecepcion(h.db, a.clave)).entrada!.existenciaAtomic,
        7,
      );
      expect(
        (await releerRecepcion(h.db, b.clave)).entrada!.existenciaAtomic,
        8,
      );
      final despues = await fotoRecepcion(h.db);
      await c.continuarCaptura('persistida');
      expect(await fotoRecepcion(h.db), despues);
    },
  );
}

class _RespuestaRetenida extends EdicionMasivaCommandService {
  _RespuestaRetenida(EdicionMasivaCommandService core) : super(core.diario);
  final commit = Completer<void>();
  final responder = Completer<void>();
  @override
  Future<ResultadoOperacionMasiva> ejecutar(OperacionEdicionMasiva op) async {
    final resultado = await super.ejecutar(op);
    if (!commit.isCompleted) {
      commit.complete();
      await responder.future;
    }
    return resultado;
  }
}
