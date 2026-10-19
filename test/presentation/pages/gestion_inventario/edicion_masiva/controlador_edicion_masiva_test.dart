import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/edicion_masiva/base_revision_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/catalogo_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/clave_variante.dart';
import 'package:pos_flutter/application/edicion_masiva/diario_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/fila_catalogo_masivo.dart';
import 'package:pos_flutter/application/edicion_masiva/lectura_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/operacion_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/registro_operacion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/resultado_operacion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/unidad_trabajo_masiva.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/borrador_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/controlador_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/resultado_guardado_masivo.dart';

import '../../../../support/product_supplier_harness.dart';
import '../../../../support/recepcion_masiva_fixture.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  group('ControladorEdicionMasiva sobre catálogo falso (sin base)', () {
    late _CatalogoFalso catalogo;
    late ControladorEdicionMasiva controller;

    setUp(() {
      catalogo = _CatalogoFalso(List.generate(120, _filaFalsa), traslapo: 5);
      controller = ControladorEdicionMasiva(
        catalogo: catalogo,
        comando: EdicionMasivaCommandService(_DiarioFalso()),
      );
    });

    tearDown(() => controller.dispose());

    test(
      'M35: páginas por ID, deduplicado y «Solo cambios» por captura',
      () async {
        await controller.buscar();
        expect(controller.filasCargadas, hasLength(100));
        expect(controller.hayMasPaginas, isTrue);

        // La segunda página se traslapa a propósito: el controlador la deduplica.
        await controller.cargarMas();
        expect(controller.filasCargadas, hasLength(120));
        expect(controller.hayMasPaginas, isFalse);
        final claves = controller.filasCargadas.map((f) => f.clave).toList();
        expect(claves.toSet(), hasLength(claves.length));

        final primera = controller.filasCargadas[3];
        final capturada = controller.filasCargadas[70];
        await controller.editarVenta(primera.clave, '15');
        await controller.editarVenta(capturada.clave, '16');
        expect(controller.modificadas, 2);
        expect(controller.filasListadas, hasLength(120));

        controller.cambiarSoloCambios(true);
        expect(controller.filasListadas.map((f) => f.clave), [
          primera.clave,
          capturada.clave,
        ]);

        await controller.cambiarBusqueda('Variante 70');
        expect(controller.filasListadas.map((f) => f.clave), [capturada.clave]);

        // El contador no depende del filtro ni de la página cargada.
        await controller.cargarMas();
        expect(controller.modificadas, 2);

        controller.retirarFila(capturada.clave);
        expect(controller.modificadas, 1);
        // Con «Solo cambios», quitar la única coincidencia vacía la lista…
        expect(controller.filasListadas, isEmpty);
        // …y limpiar la búsqueda vuelve a mostrar la captura restante.
        await controller.cambiarBusqueda('');
        expect(controller.filasListadas.map((f) => f.clave), [primera.clave]);
      },
    );

    test(
      'M38: los controladores de texto viven por ID y sobreviven filtros',
      () async {
        await controller.buscar();
        final clave = controller.filasCargadas[0].clave;
        final campo = controller.controladorTexto(
          clave,
          CampoTextoEdicion.venta,
        );
        // El TextField escribe en el controlador antes de notificar al dominio.
        campo.value = TextEditingValue(
          text: '21',
          selection: const TextSelection.collapsed(offset: 2),
        );
        await controller.editarVenta(clave, campo.text);
        expect(campo.text, '21');
        expect(
          identical(
            campo,
            controller.controladorTexto(clave, CampoTextoEdicion.venta),
          ),
          isTrue,
        );
        expect(
          controller.foco(clave).debugLabel,
          'edicion-masiva-${clave.variantId}',
        );

        controller.cambiarSoloCambios(true);
        await controller.cargarMas();
        expect(campo.text, '21');

        controller.retirarFila(clave);
        // Tras retirar se conserva el controlador y vuelve al valor actual.
        expect(
          controller.controladorTexto(clave, CampoTextoEdicion.venta).text,
          '10.00',
        );
      },
    );
  });

  group('M38: respuestas asíncronas y actualización acotada', () {
    ControladorEdicionMasiva crear(_CatalogoControlado catalogo) =>
        ControladorEdicionMasiva(
          catalogo: catalogo,
          comando: EdicionMasivaCommandService(_DiarioFalso()),
        );

    test('una búsqueda anterior no sustituye la más reciente', () async {
      final catalogo = _CatalogoControlado(List.generate(120, _filaFalsa))
        ..diferirBusquedas = true;
      final controller = crear(catalogo);
      addTearDown(controller.dispose);
      final primera = controller.buscar();
      final segunda = controller.cambiarBusqueda('Variante 70');
      catalogo.busquedas[1].complete([catalogo.filas[70]]);
      await segunda;
      catalogo.busquedas[0].complete([catalogo.filas[0]]);
      await primera;
      expect(controller.filasCargadas.single.clave, catalogo.filas[70].clave);
      expect(controller.cargando, isFalse);
    });

    test('una página anterior no contamina una búsqueda nueva', () async {
      final catalogo = _CatalogoControlado(List.generate(120, _filaFalsa));
      final controller = crear(catalogo);
      addTearDown(controller.dispose);
      await controller.buscar();
      catalogo.diferirBusquedas = true;
      final pagina = controller.cargarMas();
      final busqueda = controller.cambiarBusqueda('Variante 70');
      catalogo.busquedas[1].complete([catalogo.filas[70]]);
      await busqueda;
      catalogo.busquedas[0].complete(catalogo.filas.skip(100).toList());
      await pagina;
      expect(controller.filasCargadas.single.clave, catalogo.filas[70].clave);
    });

    test(
      'cerrar durante lectura de captura no notifica objetos destruidos',
      () async {
        final catalogo = _CatalogoControlado([_filaFalsa(0)]);
        final controller = crear(catalogo);
        await controller.buscar();
        catalogo.puertaLectura = Completer<void>();
        final edicion = controller.editarVenta(catalogo.filas[0].clave, '25');
        controller.dispose();
        catalogo.puertaLectura!.complete();
        await edicion;
      },
    );

    test(
      'pulsaciones no reconstruyen el listado, incluso con Solo cambios',
      () async {
        final catalogo = _CatalogoControlado([_filaFalsa(0)]);
        final controller = crear(catalogo);
        addTearDown(controller.dispose);
        await controller.buscar();
        final clave = catalogo.filas[0].clave;
        await controller.editarVenta(clave, '21');
        controller.cambiarSoloCambios(true);
        var estructura = 0;
        var fila = 0;
        controller.addListener(() => estructura++);
        controller.notificadorFila(clave).addListener(() => fila++);
        await controller.editarVenta(clave, '22');
        await controller.editarVenta(clave, '23');
        expect(estructura, 0);
        expect(fila, 2);
      },
    );

    test(
      'el contador excluye valores equivalentes y conserva errores',
      () async {
        final catalogo = _CatalogoControlado([_filaFalsa(0)]);
        final controller = crear(catalogo);
        addTearDown(controller.dispose);
        await controller.buscar();
        final clave = catalogo.filas[0].clave;
        await controller.editarVenta(clave, '10,00');
        expect(controller.modificadas, 0);
        await controller.editarVenta(clave, '0');
        expect(controller.modificadas, 1);
        expect(controller.erroresFila(clave), isNotEmpty);
        controller.cambiarTarea(TareaEdicionMasiva.costoProveedor);
        await controller.cambiarBusqueda('inexistente');
        expect(controller.erroresFila(clave), isNotEmpty);
        expect(controller.captura(clave)!.venta, '0');
      },
    );
  });

  group('ControladorEdicionMasiva con SQLite real', () {
    late ProductSupplierHarness h;
    final fecha = DateTime(2026, 10, 18, 13, 40);

    setUp(() => h = ProductSupplierHarness());
    tearDown(() => h.dispose());

    ControladorEdicionMasiva crear(ProductSupplierHarness harness) =>
        ControladorEdicionMasiva(
          catalogo: DriftCatalogoEdicionMasiva(harness.db),
          comando: coordinadorRecepcion(harness),
          ahora: () => fecha,
        );

    for (final mode in AppMode.values) {
      test(
        'M01: el controlador no escribe ni reserva en ${mode.name}',
        () async {
          final auditor = _ReadAudit();
          final modoH = ProductSupplierHarness(
            mode: mode,
            database: AppDatabase.forTesting(
              NativeDatabase.memory().interceptWith(auditor),
            ),
          );
          try {
            final filas = await seedRecepcion(modoH);
            final controller = crear(modoH);
            final antes = await fotoRecepcion(modoH.db);
            auditor.reset();

            await controller.buscar();
            await controller.cambiarBusqueda('Peso');
            await controller.cambiarBusqueda('');
            controller.cambiarSoloCambios(true);
            controller.cambiarSoloCambios(false);
            controller.cambiarTarea(TareaEdicionMasiva.costoProveedor);
            controller.elegirProveedorGlobal(null);
            await controller.editarCosto(filas[0].clave, '15');
            await controller.editarCantidad(filas[0].clave, '3');
            final revision = await controller.prepararRevision();
            expect(revision.cambios, hasLength(1));
            expect(revision.cambios.single.costo.establecer, isTrue);
            expect(revision.cambios.single.entrada!.cantidadAtomic, 3);
            expect(controller.tieneCapturas, isTrue);

            expect(auditor.writes, 0);
            expect(auditor.historyReads, 0);
            expect(await coordinadorRecepcion(modoH).pendientes(), isEmpty);
            expect(await fotoRecepcion(modoH.db), antes);
            controller.dispose();
          } finally {
            await modoH.dispose();
          }
        },
      );
    }

    test('M37: guardar aplica cada producto por el coordinador real', () async {
      final filas = await seedRecepcion(h);
      final peso = filas[0]; // Peso · existencia en piezas
      final piezas = filas[1];
      final controller = crear(h);
      await controller.buscar();
      await controller.editarVenta(piezas.clave, '25');
      await controller.editarCantidad(peso.clave, '3');

      final revision = await controller.prepararRevision();
      expect(revision.tieneErrores, isFalse);
      final resultados = await controller.guardar(revision);

      expect(resultados, hasLength(1));
      expect(resultados.single.aplicada, isTrue);
      expect(resultados.single.productId, piezas.clave.productId);
      expect(controller.tieneCapturas, isFalse);
      expect(controller.guardando, isFalse);
      final foto = await fotoRecepcion(h.db);
      final repetidos = await controller.guardar(revision);
      expect(
        repetidos.single.resultado!.json,
        resultados.single.resultado!.json,
      );
      expect(await fotoRecepcion(h.db), foto);

      expect((await releerRecepcion(h.db, piezas.clave)).ventaMinor, 2500);
      final pesoActualizado = await releerRecepcion(h.db, peso.clave);
      expect(pesoActualizado.entrada!.existenciaAtomic, 503);
      expect(await coordinadorRecepcion(h).pendientes(), isEmpty);
      controller.dispose();
    });

    test(
      'M38: cancelar el guardado detiene los productos no iniciados',
      () async {
        final recepcion = await seedRecepcion(h, nombre: 'Recepción');
        final otra = await seedRecepcion(h, nombre: 'Otra');
        final puerta = Completer<void>();
        final iniciado = Completer<void>();
        final controller = ControladorEdicionMasiva(
          catalogo: DriftCatalogoEdicionMasiva(h.db),
          comando: _ComandoLento(
            coordinadorRecepcion(h).diario,
            puerta.future,
            alIniciar: () {
              if (!iniciado.isCompleted) iniciado.complete();
            },
          ),
          ahora: () => fecha,
        );
        await controller.buscar();
        await controller.editarVenta(recepcion[1].clave, '25');
        await controller.editarVenta(otra[1].clave, '45');
        expect(controller.borrador.filas, hasLength(2));

        final revision = await controller.prepararRevision();
        final futuro = controller.guardar(revision);
        await iniciado.future;
        controller.cancelarGuardado();
        puerta.complete();
        final resultados = await futuro;

        // Solo se aplicó el primer producto; el resto quedó reservado y sin
        // ejecutar, y las capturas se conservan para retomar después.
        expect(resultados, hasLength(2));
        expect(resultados.first.aplicada, isTrue);
        expect(resultados.first.productId, recepcion[1].clave.productId);
        expect(resultados.last.estado, EstadoGuardadoMasivo.pendiente);
        expect(controller.tieneCapturas, isTrue);
        expect(controller.modificadas, 1);
        expect(controller.guardando, isFalse);
        expect(await coordinadorRecepcion(h).pendientes(), hasLength(1));
        expect(
          (await releerRecepcion(h.db, recepcion[1].clave)).ventaMinor,
          2500,
        );
        expect((await releerRecepcion(h.db, otra[1].clave)).ventaMinor, 2000);
        controller.dispose();
      },
    );

    test('M37: una base obsoleta falla con mensaje comprensible', () async {
      final filas = await seedRecepcion(h);
      final piezas = filas[1];
      final controller = crear(h);
      await controller.buscar();
      await controller.editarVenta(piezas.clave, '25');
      final revision = await controller.prepararRevision();

      await h.db.customStatement(
        'UPDATE products SET version = version + 1 WHERE id = ?',
        [piezas.clave.productId],
      );

      final resultados = await controller.guardar(revision);
      expect(resultados, hasLength(1));
      expect(resultados.single.aplicada, isFalse);
      expect(
        mensajeLegibleEdicionMasiva(resultados.single.error!),
        contains('cambió'),
      );
      // El fallo conserva la captura y su reserva para revisión/recuperación.
      expect(controller.tieneCapturas, isTrue);
      expect(await coordinadorRecepcion(h).pendientes(), hasLength(1));
      expect((await releerRecepcion(h.db, piezas.clave)).ventaMinor, 2000);
      controller.dispose();
    });
  });
}

/// Catálogo sintético para paginar sin tocar la base. `traslapo` hace que la
/// segunda página empiece antes del final de la anterior (deduplicación real).
class _CatalogoFalso implements CatalogoEdicionMasiva {
  _CatalogoFalso(this.filas, {this.traslapo = 0});
  final List<FilaCatalogoMasivo> filas;
  final int traslapo;

  @override
  Future<List<FilaCatalogoMasivo>> buscar({
    String busqueda = '',
    int limite = 100,
    int desplazamiento = 0,
  }) async {
    final query = busqueda.trim().toLowerCase();
    final filtradas = filas
        .where(
          (f) =>
              query.isEmpty ||
              f.nombreProducto.toLowerCase().contains(query) ||
              (f.nombreVariante ?? '').toLowerCase().contains(query),
        )
        .toList();
    final inicio = (desplazamiento - traslapo).clamp(0, filtradas.length);
    return filtradas.skip(inicio).take(limite).toList();
  }

  @override
  Future<LecturaEdicionMasiva> leer(
    Set<ClaveVariante> claves, {
    Set<String> proveedorIds = const {},
  }) async => LecturaEdicionMasiva(
    filas: {
      for (final f in filas)
        if (claves.contains(f.clave)) f.clave: f,
    },
    proveedoresActivos: proveedorIds,
  );
}

FilaCatalogoMasivo _filaFalsa(int i) {
  final productId = 'p${i ~/ 60}';
  return FilaCatalogoMasivo(
    clave: ClaveVariante(productId, 'v$i'),
    baseProducto: BaseRevisionMasiva(
      id: productId,
      version: 1,
      eventId: 'e$i',
      serverSequence: null,
    ),
    nombreProducto: 'Producto $i',
    nombreVariante: 'Variante $i',
    ventaMinor: 1000 + i,
    costoMinor: 500,
    configuracionVenta: const UnitSaleConfiguration(),
    unidadVenta: null,
    entrada: null,
    impedimentoEntrada: 'Entrada no disponible en prueba.',
    proveedores: const [],
  );
}

/// Comando real cuya ejecución espera una puerta, para observar la cancelación.
class _ComandoLento extends EdicionMasivaCommandService {
  _ComandoLento(super.diario, this.puerta, {this.alIniciar});
  final Future<void> puerta;
  final void Function()? alIniciar;

  @override
  Future<ResultadoOperacionMasiva> ejecutar(OperacionEdicionMasiva op) async {
    alIniciar?.call();
    await puerta;
    return super.ejecutar(op);
  }
}

class _DiarioFalso implements DiarioEdicionMasiva {
  Never _no() => throw UnimplementedError();
  @override
  Future<T> transaccion<T>(
    Future<T> Function(UnidadTrabajoMasiva unidad) action,
  ) => _no();
  @override
  Future<RegistroOperacionMasiva?> buscar(String operationId) => _no();
  @override
  Future<List<RegistroOperacionMasiva>> listar({
    String? batchId,
    bool soloPendientes = false,
  }) => _no();
  @override
  Future<void> reservar(OperacionEdicionMasiva operacion) => _no();
  @override
  Future<void> completar(ResultadoOperacionMasiva resultado) => _no();
  @override
  Future<void> cerrarPendientes(String batchId) => _no();
}

class _ReadAudit extends QueryInterceptor {
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
  ) async {
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

class _CatalogoControlado extends _CatalogoFalso {
  _CatalogoControlado(super.filas);
  bool diferirBusquedas = false;
  final busquedas = <Completer<List<FilaCatalogoMasivo>>>[];
  Completer<void>? puertaLectura;

  @override
  Future<List<FilaCatalogoMasivo>> buscar({
    String busqueda = '',
    int limite = 100,
    int desplazamiento = 0,
  }) {
    if (!diferirBusquedas) {
      return super.buscar(
        busqueda: busqueda,
        limite: limite,
        desplazamiento: desplazamiento,
      );
    }
    final respuesta = Completer<List<FilaCatalogoMasivo>>();
    busquedas.add(respuesta);
    return respuesta.future;
  }

  @override
  Future<LecturaEdicionMasiva> leer(
    Set<ClaveVariante> claves, {
    Set<String> proveedorIds = const {},
  }) async {
    await puertaLectura?.future;
    return super.leer(claves, proveedorIds: proveedorIds);
  }
}
