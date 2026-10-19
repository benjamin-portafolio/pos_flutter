import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import 'package:pos_flutter/domain/repositories/proveedor_repository.dart';
import 'package:pos_flutter/domain/proveedores/proveedor.dart';

import 'package:pos_flutter/application/edicion_masiva/fila_catalogo_masivo.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/controlador_edicion_masiva.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/pantalla_edicion_masiva_por_tarea.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/resultado_guardado_masivo.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/resultados_edicion_masiva.dart';

import '../../../../support/product_supplier_harness.dart';
import '../../../../support/recepcion_masiva_fixture.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  late ProductSupplierHarness h;
  setUp(() => h = ProductSupplierHarness());
  tearDown(() => h.dispose());

  Future<void> pulsar(WidgetTester tester, Finder control) async {
    if (control.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        control,
        -200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('edicion_masiva_listado')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(control);
    await tester.pumpAndSettle();
    await tester.tap(control);
    await tester.pumpAndSettle();
  }

  Future<void> vista(WidgetTester tester, String nombre) async {
    await pulsar(tester, find.byKey(const Key('edicion_masiva_vista')));
    await tester.tap(find.text(nombre).last);
    await tester.pumpAndSettle();
  }

  Future<void> buscar(WidgetTester tester, String texto) async {
    final campo = find.byKey(const Key('edicion_masiva_busqueda'));
    await tester.ensureVisible(campo);
    await tester.enterText(campo, texto);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();
  }

  Future<void> abrir(
    WidgetTester tester, {
    ProveedorRepository? proveedores,
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaEdicionMasivaPorTarea(
          catalogo: DriftCatalogoEdicionMasiva(h.db),
          comando: coordinadorRecepcion(h),
          proveedorRepository: proveedores,
          ahora: () => DateTime.utc(2026, 10, 18),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder campo(FilaCatalogoMasivo f, String nombre) =>
      find.byKey(Key('edicion_masiva_${nombre}_${f.clave.variantId}'));
  Future<void> editar(WidgetTester tester, Finder field, String texto) async {
    await tester.ensureVisible(field);
    await tester.enterText(field, texto);
    await tester.pumpAndSettle();
  }

  for (final ancho in [320.0, 360.0, 390.0, 800.0]) {
    testWidgets(
      'M16/M36/M38/M47 compacta a $ancho px: referencias, teclado, foco y selección entre vistas',
      (tester) async {
        tester.view.physicalSize = Size(ancho, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final f = (await seedRecepcion(
          h,
          medido: true,
          nombre:
              'Mercancía con un nombre muy largo que debe respetar los controles y el teclado',
        ))[1];
        await abrir(tester);
        await buscar(tester, 'Piezas');
        await vista(tester, 'Recepción compacta');
        final costo = campo(f, 'costo');
        final venta = campo(f, 'venta');
        final cantidad = campo(f, 'cantidad');
        expect(tester.getTopLeft(costo).dy, tester.getTopLeft(venta).dy);
        expect(
          tester.getTopLeft(cantidad).dy,
          greaterThan(tester.getBottomLeft(costo).dy),
        );
        expect(find.text('Precios por 1 g'), findsOneWidget);
        expect(find.text('Ingreso en Kilogramo (kg)'), findsOneWidget);
        expect(tester.widget<TextField>(venta).controller!.text, '20.00');
        await editar(tester, costo, '12');
        expect(tester.widget<TextField>(venta).controller!.text, '20.00');
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(venta).focusNode!.hasFocus, isTrue);
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(cantidad).focusNode!.hasFocus, isTrue);
        await editar(tester, cantidad, '1.25');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pumpAndSettle();
        final rect = tester.getRect(cantidad);
        final revisar = tester.getRect(
          find.byKey(const Key('edicion_masiva_revisar')),
        );
        expect(rect.top, greaterThanOrEqualTo(56));
        expect(rect.bottom, lessThanOrEqualTo(revisar.top));
        expect(revisar.bottom, lessThanOrEqualTo(360));
        expect(
          tester.widget<TextField>(cantidad).keyboardType,
          TextInputType.numberWithOptions(decimal: true),
        );
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        await vista(tester, 'Por tarea');
        await pulsar(tester, find.byKey(const Key('edicion_masiva_tarea')));
        await tester.tap(find.text('Agregar existencias').last);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(cantidad).controller!.text, '1.25');
        await editar(tester, cantidad, '-1');
        await vista(tester, 'Recepción compacta');
        expect(tester.widget<TextField>(cantidad).controller!.text, '-1');
        expect(
          tester.widget<TextField>(cantidad).decoration!.errorText,
          isNotNull,
        );
        final controlador = tester.widget<TextField>(costo).controller!;
        controlador.selection = const TextSelection.collapsed(offset: 1);
        await buscar(tester, 'sin coincidencia');
        await buscar(tester, 'Piezas');
        expect(tester.widget<TextField>(costo).controller, same(controlador));
        expect(controlador.selection.baseOffset, 1);
        expect(
          tester.widget<TextField>(cantidad).decoration!.errorText,
          isNotNull,
        );
        expect(await h.db.select(h.db.bulkEditOperations).get(), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'M03/M34/M35/M37/M40: edición conjunta, revisión, commit, resultados y recuperación explícita',
    (tester) async {
      final f = (await seedRecepcion(h))[1];
      await abrir(tester);
      await buscar(tester, 'Piezas');
      await editar(tester, campo(f, 'venta'), '26');
      await vista(tester, 'Recepción compacta');
      await editar(tester, campo(f, 'costo'), '12');
      await editar(tester, campo(f, 'cantidad'), '2');
      await vista(tester, 'Por tarea');
      await pulsar(tester, find.byKey(const Key('edicion_masiva_tarea')));
      await tester.tap(find.text('Agregar existencias').last);
      await tester.pumpAndSettle();
      await editar(tester, campo(f, 'cantidad'), '3');
      await buscar(tester, 'sin coincidencia');
      await pulsar(tester, find.byKey(const Key('edicion_masiva_revisar')));
      expect(find.text('Precio de venta: 20.00 → 26.00'), findsOneWidget);
      expect(find.text('Costo estándar: 10.00 → 12.00'), findsOneWidget);
      expect(find.textContaining('Entrada: +3 pza'), findsOneWidget);
      expect(find.text('Total de entradas: +3 pza'), findsOneWidget);
      await pulsar(tester, find.byKey(const Key('edicion_masiva_guardar')));
      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(find.textContaining('0 fallidos'), findsOneWidget);
      expect(find.textContaining('Catálogo: Registro local'), findsOneWidget);
      expect(find.textContaining('Entrada 1: Registro local'), findsOneWidget);
      final actual = await releerRecepcion(h.db, f.clave);
      expect(actual.ventaMinor, 2600);
      expect(actual.costoMinor, 1200);
      expect(actual.entrada!.existenciaAtomic, 8);
      await pulsar(tester, find.byKey(const Key('edicion_masiva_listo')));
      final antes = await fotoRecepcion(h.db);
      await pulsar(
        tester,
        find.byKey(const Key('edicion_masiva_recuperacion')),
      );
      expect(find.textContaining('Aplicado localmente'), findsOneWidget);
      final registro = (await coordinadorRecepcion(h).registros()).single;
      await pulsar(
        tester,
        find.byKey(
          Key('edicion_masiva_continuar_${registro.operacion.batchId}'),
        ),
      );
      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(
        await fotoRecepcion(h.db),
        antes,
        reason: 'Consultar y reintentar no repiten eventos/entradas',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M18 compacta: receta y ausencia de seguimiento bloquean solo entrada',
    (tester) async {
      final filas = await seedRecepcion(h);
      final receta = filas[0];
      await h.db.customStatement(
        'INSERT INTO recipe_components (variant_id, inventory_item_id, quantity_atomic) VALUES (?, ?, 1)',
        [receta.clave.variantId, receta.entrada!.recurso.id],
      );
      await abrir(tester);
      await vista(tester, 'Recepción compacta');
      for (final f in [receta, filas[2]]) {
        await buscar(tester, f.nombreVariante!);
        expect(campo(f, 'cantidad'), findsNothing);
        expect(
          find.byKey(
            Key('edicion_masiva_entrada_bloqueada_${f.clave.variantId}'),
          ),
          findsOneWidget,
        );
        expect(campo(f, 'venta'), findsOneWidget);
        expect(campo(f, 'costo'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'M22/M34/M37: recuperación obsoleta exige nueva revisión visible y conserva la cantidad',
    (tester) async {
      final f = (await seedRecepcion(h))[1];
      final core = coordinadorRecepcion(h);
      await core.confirmar(
        batchId: 'obsoleta',
        cambios: [cambioRecepcion(f, cantidad: 3)],
      );
      await h.tracking.inventoryCommands.registrarMovimiento(
        RegistrarMovimientoInventarioCommand(
          inventoryItemId: f.entrada!.recurso.id,
          movementType: TipoMovimientoInventario.stockReceipt,
          quantityDeltaAtomic: 1,
        ),
      );
      await abrir(tester);
      expect(
        find.byKey(const Key('edicion_masiva_aviso_recuperacion')),
        findsOneWidget,
      );
      final antes = await fotoRecepcion(h.db);
      await pulsar(
        tester,
        find.byKey(const Key('edicion_masiva_recuperacion')),
      );
      expect(
        find.textContaining('Recepción: Pendiente de ejecutar'),
        findsOneWidget,
      );
      expect(await fotoRecepcion(h.db), antes);
      await pulsar(
        tester,
        find.byKey(const Key('edicion_masiva_recuperar_obsoleta')),
      );
      expect(find.text('REVISIÓN DE CAMBIOS'), findsOneWidget);
      expect(find.text('Cantidad capturada: «3»'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('edicion_masiva_guardar')),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('saldo 6 pza'), findsOneWidget);
      expect(
        find.textContaining('Previsión sobre estado nuevo: 6 + 3 = 9 pza'),
        findsOneWidget,
      );
      await pulsar(
        tester,
        find.byKey(const Key('edicion_masiva_nueva_revision')),
      );
      await pulsar(tester, find.text('Revisar estado actual'));
      expect(
        find.textContaining('saldo actual 6 → previsto 9'),
        findsOneWidget,
      );
      await pulsar(tester, find.byKey(const Key('edicion_masiva_guardar')));
      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(
        (await releerRecepcion(h.db, f.clave)).entrada!.existenciaAtomic,
        9,
      );
      final registros = await core.registros();
      expect(registros, hasLength(2));
      expect(registros.map((r) => r.estado.name).toSet(), {
        'cerrada',
        'aplicada',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M09/M11/M12 compacta: proveedor global no reasigna y detalle cambia solo esa pareja',
    (tester) async {
      final filas = await seedRecepcion(h);
      final f = filas[1];
      final a = (await tester.runAsync(() => h.supplier('Proveedor A')))!;
      final b = (await tester.runAsync(() => h.supplier('Proveedor B')))!;
      final proveedores = _Proveedores([
        Proveedor(
          id: a,
          nombre: 'Proveedor A',
          version: 1,
          createdEventId: null,
          lastEventId: null,
          lastServerSequence: null,
        ),
        Proveedor(
          id: b,
          nombre: 'Proveedor B',
          version: 1,
          createdEventId: null,
          lastEventId: null,
          lastServerSequence: null,
        ),
      ]);
      await abrir(tester, proveedores: proveedores);
      await buscar(tester, 'Piezas');
      await vista(tester, 'Recepción compacta');
      Future<void> global(String nombre) async {
        await pulsar(
          tester,
          find.byKey(const Key('edicion_masiva_proveedor_global')),
        );
        await tester.tap(find.text(nombre).last);
        await tester.pumpAndSettle();
      }

      await global('Proveedor A');
      await editar(tester, campo(f, 'costo'), '12');
      await global('Proveedor B');
      expect(find.text('Detalle · proveedor propio'), findsOneWidget);
      await pulsar(
        tester,
        find.byKey(Key('edicion_masiva_detalle_${f.clave.variantId}')),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('edicion_masiva_detalle_proveedor')),
            )
            .initialValue,
        a,
      );
      await pulsar(
        tester,
        find.byKey(const Key('edicion_masiva_detalle_proveedor')),
      );
      await tester.tap(find.text('Proveedor B').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('edicion_masiva_detalle_fecha')),
        findsOneWidget,
      );
      await pulsar(
        tester,
        find.byKey(const Key('edicion_masiva_detalle_cerrar')),
      );
      await buscar(tester, 'Peso');
      await editar(tester, campo(filas[0], 'venta'), '35');
      await pulsar(tester, find.byKey(const Key('edicion_masiva_revisar')));
      expect(find.textContaining('Proveedor: Proveedor B'), findsOneWidget);
      await pulsar(tester, find.byKey(const Key('edicion_masiva_guardar')));
      final actual = await releerRecepcion(h.db, f.clave);
      expect(actual.proveedores.single.proveedorId, b);
      expect(actual.costoMinor, 1200);
      expect(actual.ventaMinor, 2000);
      expect(
        (await releerRecepcion(h.db, filas[0].clave)).proveedores,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final inverso in [false, true]) {
    testWidgets(
      'Entrega por evento con aceptación parcial (inverso=$inverso), SQLite real sin transporte',
      (tester) async {
        final remoto = ProductSupplierHarness(mode: AppMode.serverSync);
        addTearDown(remoto.dispose);
        final f = (await seedRecepcion(remoto))[1];
        final core = coordinadorRecepcion(remoto);
        final ops = await core.confirmar(
          batchId: 'entrega',
          cambios: [cambioRecepcion(f, costo: 1300, cantidad: 2)],
        );
        final resultado = await core.ejecutar(ops.single);
        final c = ControladorEdicionMasiva(
          catalogo: DriftCatalogoEdicionMasiva(remoto.db),
          comando: core,
        );
        addTearDown(c.dispose);
        await remoto.db.customStatement(
          'UPDATE events SET delivery_status = ? WHERE event_id = ?',
          [inverso ? 'rejected' : 'delivered', resultado.catalogEventId],
        );
        await remoto.db.customStatement(
          'UPDATE events SET delivery_status = ?, rejection_reason = ? WHERE event_id = ?',
          [
            inverso ? 'delivered' : 'conflict',
            inverso ? null : 'Saldo concurrente',
            resultado.entradas.single.eventId,
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ResultadosEdicionMasiva(
              controller: c,
              resultados: [
                ResultadoGuardadoMasivo.aplicada(
                  productId: f.clave.productId,
                  resultado: resultado,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            inverso ? 'Catálogo: Rechazado' : 'Catálogo: Aceptado',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            inverso ? 'Entrada 1: Aceptado' : 'Entrada 1: Conflicto',
          ),
          findsOneWidget,
        );
        final antes = await fotoRecepcion(remoto.db);
        await pulsar(tester, find.text('Actualizar entrega'));
        await core.ejecutar(ops.single);
        expect(await fotoRecepcion(remoto.db), antes);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Proveedores implements ProveedorRepository {
  _Proveedores(this.valores);
  final List<Proveedor> valores;
  @override
  Stream<List<Proveedor>> watchProveedores() => Stream.value(valores);
}
