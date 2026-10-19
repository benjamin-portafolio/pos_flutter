import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/clave_variante.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/borrador_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/fila_revision_masiva.dart';

import '../../../../support/product_supplier_harness.dart';

const _grande = ClaveVariante('p1', 'v11');
const _chica = ClaveVariante('p1', 'v12');
const _receta = ClaveVariante('p1', 'v13');
const _libre = ClaveVariante('p1', 'v14');
const _otro = ClaveVariante('p2', 'v21');
const _medido = ClaveVariante('p3', 'v31');
const _proveedorA = '20000000-0000-4000-8000-000000000001';
const _proveedorB = '20000000-0000-4000-8000-000000000002';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  late AppDatabase db;
  late _ReadAudit audit;
  late DriftCatalogoEdicionMasiva catalogo;
  late BorradorEdicionMasiva borrador;
  var fecha = DateTime(2026, 10, 18, 13, 40);

  setUp(() async {
    fecha = DateTime(2026, 10, 18, 13, 40);
    audit = _ReadAudit();
    db = AppDatabase.forTesting(NativeDatabase.memory().interceptWith(audit));
    await _seed(db);
    catalogo = DriftCatalogoEdicionMasiva(db);
    borrador = BorradorEdicionMasiva(catalogo: catalogo, ahora: () => fecha);
    audit.reset();
  });
  tearDown(() => db.close());

  test(
    'M02: página ligera por IDs, nombres repetidos y varios del mismo producto',
    () async {
      final pagina = await catalogo.buscar(limite: 2);
      final siguiente = await catalogo.buscar(limite: 2, desplazamiento: 2);
      expect(pagina.map((f) => f.clave), [_grande, _chica]);
      expect(siguiente.map((f) => f.clave), [_receta, _libre]);
      expect(await catalogo.buscar(busqueda: '  grande  '), hasLength(2));
      expect(await catalogo.buscar(busqueda: '%'), isEmpty);
      expect(await catalogo.buscar(busqueda: "' OR 1=1 --"), isEmpty);
      await borrador.editarVenta(_grande, '21');
      await borrador.editarVenta(_chica, '22');
      await borrador.editarVenta(_otro, '23');
      // Un nuevo orden del listado no retargetea una captura existente.
      await db.customStatement(
        "UPDATE product_variants SET sort_order=9 WHERE id='v11'",
      );
      await db.customStatement(
        "UPDATE product_variants SET sort_order=0 WHERE id='v12'",
      );
      await db.customStatement(
        "UPDATE product_variants SET sort_order=1 WHERE id='v11'",
      );
      final cambios = (await borrador.prepararRevision()).cambios;
      expect(
        {for (final c in cambios) c.clave: c.venta.valor},
        {_grande: 2100, _chica: 2200, _otro: 2300},
      );
      expect(
        identical(cambios[0].baseProducto, cambios[1].baseProducto),
        isTrue,
      );
      expect(audit.historyReads, 0);
    },
  );

  test(
    'M03: ambas vistas sustituyen cantidad, conservan texto/selección/error',
    () async {
      await borrador.editarCantidad(_grande, '2');
      await borrador.editarVenta(_grande, 'mal');
      borrador.seleccion = _grande;
      borrador.vista = VistaEdicionMasiva.recepcionCompacta;
      borrador.tarea = TareaEdicionMasiva.agregarExistencias;
      borrador.busqueda = 'inexistente';
      borrador.soloCambios = true;
      await borrador.buscar();
      final conError = await borrador.prepararRevision();
      expect(conError.filas.single.errores, contains(CampoEdicionMasiva.venta));
      expect(borrador.filasVisibles(conError), isEmpty);
      expect(borrador.filas[_grande]!.venta, 'mal');
      expect(borrador.seleccion, _grande);
      await borrador.editarCantidad(_grande, '3,500');
      await borrador.editarVenta(_grande, '20');
      borrador.vista = VistaEdicionMasiva.porTarea;
      await borrador.editarCantidad(_grande, '3,500');
      borrador.busqueda = '';
      final revision = await borrador.prepararRevision();
      expect(revision.cambios, hasLength(1));
      expect(revision.cambios.single.entrada!.cantidadAtomic, 3500);
      expect(revision.cambios.single.entrada!.existenciaPrevistaAtomic, 5500);
      expect(revision.cambios.single.venta.establecer, isFalse);
      expect(borrador.filasVisibles(revision), hasLength(1));
      expect(audit.writes, 0);
    },
  );

  test(
    'capturas concurrentes de la misma fila conservan ambos campos',
    () async {
      await Future.wait([
        borrador.editarVenta(_grande, '25'),
        borrador.editarCosto(_grande, '15'),
        borrador.editarCantidad(_grande, '4'),
      ]);
      final cambio = (await borrador.prepararRevision()).cambios.single;
      expect(cambio.venta.valor, 2500);
      expect(cambio.costo.valor, 1500);
      expect(cambio.entrada!.cantidadAtomic, 4000);
      expect(
        audit.catalogReads,
        2,
      ); // primera captura y revisión, sin duplicar carga
    },
  );

  test(
    'M05: costo desconocido sin tocar y venta independiente del costo',
    () async {
      await borrador.editarVenta(_chica, '21');
      var cambio = (await borrador.prepararRevision()).cambios.single;
      expect(cambio.costo.establecer, isFalse);
      expect(borrador.filas[_chica]!.original.costoMinor, isNull);
      await borrador.editarCosto(_chica, '0');
      cambio = (await borrador.prepararRevision()).cambios.single;
      expect(cambio.costo.valor, 0);
      expect(cambio.venta.valor, 2100);
      await borrador.editarCosto(_grande, '15');
      cambio = (await borrador.prepararRevision()).cambios.last;
      expect(cambio.venta.establecer, isFalse);
      expect(borrador.filas[_grande]!.original.ventaMinor, 2000);
    },
  );

  test(
    'la primera captura conserva el proveedor visible durante la lectura',
    () async {
      borrador.elegirProveedorGlobal(_proveedorA);
      final captura = borrador.editarCosto(_grande, '15');
      borrador.elegirProveedorGlobal(_proveedorB);
      await captura;
      expect(
        (await borrador.prepararRevision())
            .cambios
            .single
            .precioProveedor!
            .proveedorId,
        _proveedorA,
      );
    },
  );

  test(
    'lectura por conjuntos de más de 400 destinos, sin historial ni detalles',
    () async {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: 'grande',
              name: 'Catálogo',
              lastEventId: const Value('base'),
            ),
          );
      await db.batch(
        (batch) => batch.insertAll(db.productVariants, [
          for (var i = 0; i < 405; i++)
            ProductVariantsCompanion.insert(
              id: 'variante-$i',
              productId: 'grande',
              salePriceMinor: 2000,
              sortOrder: i,
            ),
        ]),
      );
      audit.reset();
      final lectura = await catalogo.leer({
        for (var i = 0; i < 405; i++) ClaveVariante('grande', 'variante-$i'),
      });
      expect(lectura.filas, hasLength(405));
      expect(audit.catalogReads, 2);
      expect(await catalogo.buscar(limite: 200), hasLength(200));
      expect(audit.historyReads, 0);
      expect(audit.writes, 0);
    },
  );

  for (final captura in [
    (campo: CampoEdicionMasiva.costo, texto: ''),
    (campo: CampoEdicionMasiva.costo, texto: ' '),
    (campo: CampoEdicionMasiva.venta, texto: ''),
    (campo: CampoEdicionMasiva.venta, texto: '0'),
  ]) {
    test(
      'M05: ${captura.campo.name} «${captura.texto}» produce error sin retirar valor',
      () async {
        if (captura.campo == CampoEdicionMasiva.costo) {
          await borrador.editarCosto(_grande, captura.texto);
        } else {
          await borrador.editarVenta(_grande, captura.texto);
        }
        final revision = await borrador.prepararRevision();
        expect(revision.filas.single.errores, contains(captura.campo));
        expect(() => revision.cambios, throwsStateError);
        expect(audit.writes, 0);
      },
    );
  }

  for (final cantidad in ['', ' ', '0', '0,000']) {
    test('M06/M25: cantidad «$cantidad» no prepara una entrada', () async {
      await borrador.editarCantidad(_grande, cantidad);
      final revision = await borrador.prepararRevision();
      expect(revision.cambios, isEmpty);
      expect(revision.filas.single.estado, EstadoFilaMasiva.sinCambios);
      expect(audit.writes, 0);
    });
  }

  for (final cantidad in ['-1', '1.0001', '1e2', '9007199254740.992', 'no']) {
    test('M06: cantidad inválida «$cantidad» se conserva como error', () async {
      await borrador.editarCantidad(_grande, cantidad);
      final revision = await borrador.prepararRevision();
      expect(
        revision.filas.single.errores,
        contains(CampoEdicionMasiva.cantidad),
      );
      expect(borrador.filas[_grande]!.cantidad, cantidad);
    });
  }

  test('M06: piezas enteras y magnitud no representable en átomos', () async {
    await borrador.editarCantidad(_chica, '1.5');
    expect((await borrador.prepararRevision()).tieneErrores, isTrue);
    borrador.retirarFila(_chica);
    await db
        .into(db.units)
        .insert(
          UnitsCompanion.insert(
            unitId: 'tercios',
            code: 'tercios',
            name: 'Tercios',
            symbol: 't',
            dimension: 'mass',
            atomicFactor: 3,
            maxFractionDigits: 2,
          ),
        );
    await db.customStatement(
      "UPDATE inventory_items SET default_unit_id='tercios' WHERE id='r1'",
    );
    await borrador.editarCantidad(_grande, '0.1');
    expect(
      (await borrador.prepararRevision())
          .filas
          .single
          .errores[CampoEdicionMasiva.cantidad],
      contains('no es representable'),
    );
  });

  test('M06: la suma prevista tampoco puede exceder el rango seguro', () async {
    await db.customStatement(
      'UPDATE inventory_balances SET '
      "quantity_on_hand_atomic=9007199254740991 WHERE inventory_item_id='r1'",
    );
    await borrador.editarCantidad(_grande, '0.001');
    expect(
      (await borrador.prepararRevision()).filas.single.errores,
      contains(CampoEdicionMasiva.cantidad),
    );
  });

  test(
    'M11: proveedor global solo predetermina nuevas capturas de costo',
    () async {
      borrador.elegirProveedorGlobal(_proveedorA);
      expect((await borrador.prepararRevision()).filas, isEmpty);
      await borrador.editarVenta(_grande, '21');
      expect(
        (await borrador.prepararRevision()).cambios.single.precioProveedor,
        isNull,
      );
      await borrador.editarCosto(_grande, '12');
      final fechaInicial = borrador.filas[_grande]!.fechaInformada;
      fecha = fecha.add(const Duration(days: 1));
      borrador.elegirProveedorGlobal(_proveedorB);
      await borrador.editarCosto(_grande, '13');
      await borrador.editarCosto(_chica, '4');
      final cambios = (await borrador.prepararRevision()).cambios;
      expect(cambios[0].precioProveedor!.proveedorId, _proveedorA);
      expect(cambios[1].precioProveedor!.proveedorId, _proveedorB);
      expect(borrador.filas[_grande]!.fechaInformada, fechaInicial);
      expect(
        cambios[0].precioProveedor!.fechaInformadaMs,
        fechaInicial!.toUtc().millisecondsSinceEpoch,
      );
      expect(audit.writes, 0);
    },
  );

  test(
    'costo capturado sin proveedor conserva esa intención al cambiar el global',
    () async {
      await borrador.editarCosto(_grande, '15');
      borrador.elegirProveedorGlobal(_proveedorB);
      await borrador.editarCosto(_grande, '16');
      expect(
        (await borrador.prepararRevision()).cambios.single.precioProveedor,
        isNull,
      );
      await borrador.editarProveedor(
        _grande,
        _proveedorB,
        fecha: DateTime.utc(2026, 10, 1),
      );
      expect(
        (await borrador.prepararRevision())
            .cambios
            .single
            .precioProveedor!
            .proveedorId,
        _proveedorB,
      );
    },
  );

  test(
    'clasifica precio de pareja, conserva fecha idéntica y exige costo conocido',
    () async {
      borrador.elegirProveedorGlobal(_proveedorA);
      await borrador.editarCosto(_grande, '10'); // pareja=10, estándar=12
      var cambio = (await borrador.prepararRevision()).cambios.single;
      expect(cambio.costo.valor, 1000);
      expect(cambio.precioProveedor, isNull); // fecha original no se refresca
      await borrador.editarCosto(_grande, '12'); // estándar=12, pareja distinta
      cambio = (await borrador.prepararRevision()).cambios.single;
      expect(cambio.costo.establecer, isFalse);
      expect(cambio.precioProveedor!.precioInformadoMenor, 1200);
      await borrador.editarProveedor(_chica, _proveedorB);
      expect(
        (await borrador.prepararRevision()).filas.last.errores,
        contains(CampoEdicionMasiva.costo),
      );
    },
  );

  test(
    'proveedor/fecha inválidos y proveedor inactivo impiden revisión completa',
    () async {
      await borrador.editarProveedor(_grande, 'inexistente');
      expect(
        (await borrador.prepararRevision()).filas.single.errores,
        contains(CampoEdicionMasiva.proveedor),
      );
      await borrador.editarProveedor(
        _grande,
        _proveedorB,
        fecha: DateTime.utc(1969),
      );
      expect(
        (await borrador.prepararRevision()).filas.single.errores,
        contains(CampoEdicionMasiva.fecha),
      );
      await borrador.editarProveedor(
        _grande,
        _proveedorB,
        fecha: DateTime.utc(2026),
      );
      await db.customStatement(
        "UPDATE suppliers SET active=0 WHERE id='$_proveedorB'",
      );
      expect(
        (await borrador.prepararRevision()).filas.single.errores,
        contains(CampoEdicionMasiva.proveedor),
      );
    },
  );

  test(
    'M16: referencia comercial medida y unidad de entrada son independientes',
    () async {
      await borrador.editarVenta(_medido, '30');
      await borrador.editarCosto(_medido, '13');
      await borrador.editarCantidad(_medido, '1.5');
      final revision = await borrador.prepararRevision();
      final fila = revision.filas.single;
      expect(fila.captura.original.unidadVenta!.id, InventoryUnitIds.gram);
      expect(
        fila.captura.original.configuracionVenta.priceReferenceQuantityAtomic,
        250,
      );
      expect(fila.cambio!.venta.valor, 3000);
      expect(fila.cambio!.costo.valor, 1300);
      expect(fila.cambio!.entrada!.base.unidad.id, InventoryUnitIds.kilogram);
      expect(fila.cambio!.entrada!.cantidadAtomic, 1500);
      expect(fila.cambio!.entrada!.existenciaPrevistaAtomic, 3500);
    },
  );

  for (final clave in [_receta, _libre]) {
    test(
      'M18: ${clave.variantId} permite cambios comerciales y explica entrada bloqueada',
      () async {
        final fila = (await catalogo.leer({clave})).filas[clave]!;
        expect(fila.entrada, isNull);
        expect(fila.impedimentoEntrada, contains('Inventario'));
        await borrador.editarVenta(clave, '21');
        expect(
          (await borrador.prepararRevision()).cambios.single.venta.valor,
          2100,
        );
        await borrador.editarCantidad(clave, '1');
        expect(
          (await borrador.prepararRevision()).filas.single.errores,
          contains(CampoEdicionMasiva.cantidad),
        );
        await borrador.editarCantidad(clave, '0');
        expect((await borrador.prepararRevision()).tieneErrores, isFalse);
      },
    );
  }

  test(
    'M25: estado idéntico, incluido proveedor, omite todo sin escribir',
    () async {
      final antes = await _estado(db);
      audit.reset();
      await borrador.editarVenta(_grande, '20,00');
      await borrador.editarCantidad(_grande, '0');
      await borrador.editarCosto(_libre, '12');
      final revision = await borrador.prepararRevision();
      expect(revision.cambios, isEmpty);
      expect(
        revision.filas.every((f) => f.estado == EstadoFilaMasiva.sinCambios),
        isTrue,
      );
      borrador.soloCambios = true;
      expect(borrador.filasVisibles(revision), isEmpty);
      expect(audit.writes, 0);
      expect(await _estado(db), antes);
    },
  );

  for (final cambio in [
    "UPDATE products SET version=2, last_event_id='otro' WHERE id='p1'",
    "UPDATE inventory_items SET version=2, last_event_id='otro' WHERE id='r1'",
    "UPDATE inventory_balances SET quantity_on_hand_atomic=2001, version=2, last_event_id='otro' WHERE inventory_item_id='r1'",
    "UPDATE inventory_items SET default_unit_id='${InventoryUnitIds.gram}' WHERE id='r1'",
    "UPDATE inventory_items SET active=0 WHERE id='r1'",
    "UPDATE product_variants SET inventory_item_id=NULL WHERE id='v11'",
  ]) {
    test('base esperada queda fija ante cambio: $cambio', () async {
      await borrador.editarCantidad(_grande, '1');
      final base = borrador.filas[_grande]!.original.entrada;
      await db.customStatement(cambio);
      final revision = await borrador.prepararRevision();
      expect(revision.filas.single.errores, contains(CampoEdicionMasiva.base));
      expect(
        identical(borrador.filas[_grande]!.original.entrada, base),
        isTrue,
      );
      expect(borrador.filas[_grande]!.cantidad, '1');
      expect(() => revision.cambios, throwsStateError);
    });
  }

  test('eco de la misma base conserva intenciones sin invalidarlas', () async {
    await borrador.editarCantidad(_grande, '1');
    await db.customStatement(
      "UPDATE products SET last_server_sequence=99 WHERE id='p1'",
    );
    await db.customStatement(
      "UPDATE inventory_items SET last_server_sequence=100 WHERE id='r1'",
    );
    await db.customStatement(
      "UPDATE inventory_balances SET last_server_sequence=100 WHERE inventory_item_id='r1'",
    );
    final cambio = (await borrador.prepararRevision()).cambios.single;
    expect(cambio.baseProducto.serverSequence, isNull);
    expect(cambio.entrada!.base.recurso.serverSequence, isNull);
  });

  test(
    'lectura rechaza pertenencia incorrecta, retirados y límites de página',
    () async {
      expect(
        (await catalogo.leer({const ClaveVariante('p2', 'v11')})).filas,
        isEmpty,
      );
      expect(
        () => borrador.editarVenta(const ClaveVariante('p2', 'v11'), '20'),
        throwsStateError,
      );
      await borrador.editarVenta(_grande, '21');
      await db.customStatement(
        "UPDATE product_variants SET active=0 WHERE id='v11'",
      );
      expect((await borrador.prepararRevision()).tieneErrores, isTrue);
      expect((await catalogo.buscar()).any((f) => f.clave == _grande), isFalse);
      expect(() => catalogo.buscar(limite: 201), throwsArgumentError);
      expect(() => catalogo.buscar(desplazamiento: -1), throwsArgumentError);
    },
  );

  test(
    'una variante nueva de producto ya capturado conserva su base inicial',
    () async {
      await borrador.editarVenta(_grande, '21');
      await db.customStatement(
        "UPDATE products SET version=2, last_event_id='nuevo' WHERE id='p1'",
      );
      await borrador.editarVenta(_chica, '22');
      final revision = await borrador.prepararRevision();
      expect(
        revision.filas.every(
          (f) => f.errores.containsKey(CampoEdicionMasiva.base),
        ),
        isTrue,
      );
      borrador.retirarFila(_grande);
      borrador.retirarFila(_chica);
      expect((await borrador.prepararRevision()).cambios, isEmpty);
      await borrador.editarVenta(_chica, '22');
      expect(
        (await borrador.prepararRevision()).cambios.single.baseProducto.eventId,
        'nuevo',
      );
    },
  );

  test(
    'lectura consistente aunque otra conexión cambie precio/pareja entre consultas',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'edicion-masiva-lectura',
      );
      final file = File('${directory.path}/catalogo.sqlite');
      final auditor = _ReadAudit();
      final lector = AppDatabase.forTesting(
        NativeDatabase(file).interceptWith(auditor),
      );
      final escritor = AppDatabase.forTesting(NativeDatabase(file));
      try {
        await _seed(lector);
        await lector.customStatement('PRAGMA journal_mode=WAL');
        await escritor.customSelect('SELECT 1').get();
        Future<void> actualizar() => escritor.transaction(() async {
          await escritor.customStatement(
            "UPDATE product_variants SET sale_price_minor=9900 WHERE id='v11'",
          );
          await escritor.customStatement(
            "UPDATE variant_suppliers SET quoted_price_minor=9900 WHERE variant_id='v11'",
          );
        });
        var bloqueado = false;
        auditor.despuesCatalogo = () async {
          try {
            await actualizar();
          } on SqliteException catch (e) {
            if (e.resultCode != 5) rethrow;
            // NativeDatabase usa BEGIN IMMEDIATE: la transacción de lectura
            // conserva la foto bloqueando al escritor hasta terminarla.
            bloqueado = true;
          }
        };
        final reader = DriftCatalogoEdicionMasiva(lector);
        final original = (await reader.leer({_grande})).filas[_grande]!;
        expect(original.ventaMinor, 2000);
        expect(original.proveedores.single.precioInformadoMenor, 1000);
        if (bloqueado) {
          await actualizar();
        }
        final nuevo = (await reader.leer({_grande})).filas[_grande]!;
        expect(nuevo.ventaMinor, 9900);
        expect(nuevo.proveedores.single.precioInformadoMenor, 9900);
      } finally {
        await escritor.close();
        await lector.close();
        await directory.delete(recursive: true);
      }
    },
  );

  for (final mode in AppMode.values) {
    test(
      'M01: abrir/buscar/editar/revisar no escribe ni reserva en ${mode.name}',
      () async {
        final auditor = _ReadAudit();
        final h = ProductSupplierHarness(
          mode: mode,
          database: AppDatabase.forTesting(
            NativeDatabase.memory().interceptWith(auditor),
          ),
        );
        try {
          final producto = await h.tracking.create(initial: '2');
          final clave = ClaveVariante(producto.productId, producto.variantId);
          final draft = BorradorEdicionMasiva(
            catalogo: DriftCatalogoEdicionMasiva(h.db),
          );
          final antes = await _estado(h.db);
          auditor.reset();
          expect((await draft.prepararRevision()).filas, isEmpty);
          await draft.buscar();
          await draft.editarVenta(clave, '15');
          await draft.editarCantidad(clave, '3');
          draft.vista = VistaEdicionMasiva.recepcionCompacta;
          draft.soloCambios = true;
          draft.busqueda = 'sin coincidencias';
          await draft.buscar();
          final revision = await draft.prepararRevision();
          expect(revision.cambios.single.entrada!.cantidadAtomic, 3);
          expect(auditor.writes, 0);
          expect(auditor.historyReads, 0);
          expect(
            await _estado(h.db),
            antes,
          ); // todas las tablas, refs/undo incluidos
        } finally {
          await h.dispose();
        }
      },
    );
  }
}

Future<void> _seed(AppDatabase db) async {
  for (final id in [_proveedorA, _proveedorB]) {
    await db
        .into(db.suppliers)
        .insert(SuppliersCompanion.insert(id: id, name: id));
  }
  for (final id in ['r1', 'r2', 'r3', 'r4']) {
    await db
        .into(db.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            id: id,
            name: id,
            defaultUnitId: id == 'r2'
                ? InventoryUnitIds.piece
                : InventoryUnitIds.kilogram,
            lastEventId: Value('$id-event'),
          ),
        );
    await db
        .into(db.inventoryBalances)
        .insert(
          InventoryBalancesCompanion.insert(
            inventoryItemId: id,
            quantityOnHandAtomic: 2000,
            quantityAvailableAtomic: 2000,
            lastEventId: '$id-event',
          ),
        );
  }
  for (final id in ['p1', 'p2', 'p3']) {
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: id,
            name: id == 'p3' ? 'Medido' : 'Duplicado',
            lastEventId: Value('$id-event'),
            saleMode: Value(id == 'p3' ? 'measured' : 'unit'),
            saleUnitId: Value(id == 'p3' ? InventoryUnitIds.gram : null),
            priceReferenceQuantityAtomic: Value(id == 'p3' ? 250 : null),
          ),
        );
  }
  for (final v in [
    (id: 'v11', product: 'p1', nombre: 'Grande', orden: 0, recurso: 'r1'),
    (id: 'v12', product: 'p1', nombre: 'Chica', orden: 1, recurso: 'r2'),
    (id: 'v13', product: 'p1', nombre: 'Receta', orden: 2, recurso: null),
    (id: 'v14', product: 'p1', nombre: 'Libre', orden: 3, recurso: null),
    (id: 'v21', product: 'p2', nombre: 'Grande', orden: 0, recurso: 'r3'),
    (id: 'v31', product: 'p3', nombre: 'Medida', orden: 0, recurso: 'r4'),
  ]) {
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: v.id,
            productId: v.product,
            name: Value(v.nombre),
            nameKey: Value(v.nombre.toLowerCase()),
            salePriceMinor: 2000,
            standardCostMinor: Value(v.id == 'v12' ? null : 1200),
            sortOrder: v.orden,
            inventoryItemId: Value(v.recurso),
          ),
        );
  }
  await db
      .into(db.recipeComponents)
      .insert(
        RecipeComponentsCompanion.insert(
          variantId: 'v13',
          inventoryItemId: 'r1',
          quantityAtomic: 1,
        ),
      );
  await db
      .into(db.variantSuppliers)
      .insert(
        VariantSuppliersCompanion.insert(
          variantId: 'v11',
          supplierId: _proveedorA,
          quotedPriceMinor: 1000,
          quotedAtMs: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
        ),
      );
}

Future<String> _estado(AppDatabase db) async {
  final tablas = <String, Object?>{};
  for (final tabla in db.allTables) {
    tablas[tabla.actualTableName] =
        (await db
                .customSelect(
                  'SELECT * FROM "${tabla.actualTableName}" ORDER BY rowid',
                )
                .get())
            .map((r) => r.data)
            .toList();
  }
  return jsonEncode(tablas);
}

class _ReadAudit extends QueryInterceptor {
  int writes = 0;
  int catalogReads = 0;
  int historyReads = 0;
  Future<void> Function()? despuesCatalogo;

  void reset() {
    writes = 0;
    catalogReads = 0;
    historyReads = 0;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor e,
    String s,
    List<Object?> a,
  ) async {
    if (s.contains('"events"')) historyReads++;
    final rows = await super.runSelect(e, s, a);
    if (s.contains('FROM products p JOIN')) {
      catalogReads++;
      final callback = despuesCatalogo;
      despuesCatalogo = null;
      await callback?.call();
    }
    return rows;
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
