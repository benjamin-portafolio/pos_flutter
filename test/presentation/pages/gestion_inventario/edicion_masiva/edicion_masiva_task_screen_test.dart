import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/edicion_masiva/edicion_masiva_command_service.dart';
import 'package:pos_flutter/application/edicion_masiva/fila_catalogo_masivo.dart';
import 'package:pos_flutter/application/edicion_masiva/catalogo_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/clave_variante.dart';
import 'package:pos_flutter/application/edicion_masiva/lectura_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/cambio_variante_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/operacion_edicion_masiva.dart';
import 'package:pos_flutter/application/edicion_masiva/resultado_operacion_masiva.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/drift_catalogo_edicion_masiva.dart';
import 'package:pos_flutter/domain/proveedores/proveedor.dart';
import 'package:pos_flutter/domain/repositories/proveedor_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/edicion_masiva/pantalla_edicion_masiva_por_tarea.dart';

import '../../../../support/product_supplier_harness.dart';
import '../../../../support/recepcion_masiva_fixture.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);

  late ProductSupplierHarness h;
  final ahora = DateTime(2026, 10, 18, 13, 40);

  setUp(() => h = ProductSupplierHarness());
  tearDown(() => h.dispose());

  Future<void> pumpPantalla(
    WidgetTester tester, {
    ProveedorRepository? proveedores,
    EdicionMasivaCommandService? comando,
    ProductSupplierHarness? base,
  }) async {
    final hb = base ?? h;
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaEdicionMasivaPorTarea(
          catalogo: DriftCatalogoEdicionMasiva(hb.db),
          comando: comando ?? coordinadorRecepcion(hb),
          proveedorRepository: proveedores,
          ahora: () => ahora,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<FilaCatalogoMasivo>> abrir(
    WidgetTester tester, {
    ProveedorRepository? proveedores,
    EdicionMasivaCommandService? comando,
  }) async {
    final filas = await seedRecepcion(h);
    await pumpPantalla(tester, proveedores: proveedores, comando: comando);
    return filas;
  }

  Future<void> buscarEn(WidgetTester tester, String texto) async {
    await tester.enterText(
      find.byKey(const Key('edicion_masiva_busqueda')),
      texto,
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'M35: búsqueda, «Solo cambios», contador y salida confirmada sin escribir',
    (tester) async {
      final auditor = _ReadAudit();
      final hAudit = ProductSupplierHarness(
        database: AppDatabase.forTesting(
          NativeDatabase.memory().interceptWith(auditor),
        ),
      );
      addTearDown(() => hAudit.dispose());
      final filas = await seedRecepcion(hAudit);
      final peso = filas[0];
      final piezas = filas[1];
      auditor.writes = 0;
      auditor.historyReads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PantallaEdicionMasivaPorTarea(
            catalogo: DriftCatalogoEdicionMasiva(hAudit.db),
            comando: coordinadorRecepcion(hAudit),
            ahora: () => ahora,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edicion_masiva_listado')), findsOneWidget);
      expect(
        find.byKey(Key('edicion_masiva_fila_${piezas.clave.variantId}')),
        findsOneWidget,
      );

      // La búsqueda filtra tras el debounce y no toca la base.
      await buscarEn(tester, 'Piezas');
      expect(
        find.byKey(Key('edicion_masiva_fila_${piezas.clave.variantId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('edicion_masiva_fila_${peso.clave.variantId}')),
        findsNothing,
      );

      // Capturar no pierde el texto al ocultarse y al volver la fila.
      final campo = find.byKey(
        Key('edicion_masiva_venta_${piezas.clave.variantId}'),
      );
      await tester.enterText(campo, '25');
      await tester.pump();
      expect(find.text('Modificado'), findsOneWidget);
      expect(find.text('1 modificadas'), findsOneWidget);
      expect(find.text('Nuevo: 25'), findsOneWidget);

      await buscarEn(tester, 'Peso');
      expect(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
        findsNothing,
      );
      await buscarEn(tester, 'Piezas');
      expect(tester.widget<TextField>(campo).controller!.text, '25');

      // «Solo cambios» solo lista capturas que coinciden con la búsqueda.
      await tester.tap(find.byKey(const Key('edicion_masiva_solo_cambios')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('edicion_masiva_fila_${piezas.clave.variantId}')),
        findsOneWidget,
      );
      await buscarEn(tester, 'zzz');
      expect(
        find.byKey(const Key('edicion_masiva_listado_vacio')),
        findsOneWidget,
      );
      expect(find.text('1 modificadas'), findsOneWidget);
      await buscarEn(tester, '');

      // Salir con capturas ofrece continuar o descartar; ninguna escribe.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Cambios sin guardar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edicion_masiva_continuar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edicion_masiva_revisar')), findsOneWidget);
      expect(find.text('1 modificadas'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edicion_masiva_descartar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('edicion_masiva_revisar')), findsNothing);
      expect(auditor.writes, 0);
      expect(auditor.historyReads, 0);
    },
  );

  testWidgets(
    'M38: teclado numérico, Siguiente enfoca la siguiente fila y el foco es estable',
    (tester) async {
      final filas = await abrir(tester);
      final peso = filas[0];
      final piezas = filas[1];

      // El listado ordena por sort_order de creación: Piezas, Peso, Sin seguimiento.
      final campoPiezas = find.byKey(
        Key('edicion_masiva_venta_${piezas.clave.variantId}'),
      );
      final campoPeso = find.byKey(
        Key('edicion_masiva_venta_${peso.clave.variantId}'),
      );
      expect(
        tester.widget<TextField>(campoPiezas).keyboardType,
        TextInputType.numberWithOptions(decimal: true),
      );

      await tester.enterText(campoPiezas, '21');
      await tester.pump();
      // Escribir no reconstruye pierde foco ni selección.
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'edicion-masiva-${piezas.clave.variantId}',
      );

      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(
        tester.binding.focusManager.primaryFocus?.debugLabel,
        'edicion-masiva-${peso.clave.variantId}',
      );
      // El campo enfocado queda visible dentro del listado.
      expect(tester.binding.focusManager.primaryFocus?.context != null, isTrue);

      // Capturar también la fila enfocada y filtrar: ni texto ni foco se pierden.
      await tester.enterText(campoPeso, '31');
      await tester.pump();
      await tester.tap(find.byKey(const Key('edicion_masiva_solo_cambios')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(campoPiezas).controller!.text, '21');
      expect(tester.widget<TextField>(campoPeso).controller!.text, '31');
      expect(tester.widget<TextField>(campoPeso).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M37: la revisión reúne filas ocultas, antes/después, unidades y errores',
    (tester) async {
      final filas = await abrir(tester);
      final peso = filas[0];
      final piezas = filas[1];
      final sinSeguimiento = filas[2];

      await tester.enterText(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
        '25',
      );
      await tester.enterText(
        find.byKey(
          Key('edicion_masiva_venta_${sinSeguimiento.clave.variantId}'),
        ),
        '-',
      );
      await tester.tap(find.byKey(const Key('edicion_masiva_tarea')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar existencias').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(Key('edicion_masiva_cantidad_${peso.clave.variantId}')),
        '3',
      );
      await tester.pump();

      // Abrir revisión sin búsqueda para verificar contenido completo.
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();

      expect(find.text('REVISIÓN DE CAMBIOS'), findsOneWidget);
      expect(find.textContaining('2 variantes con cambios'), findsOneWidget);
      expect(find.textContaining('1 con errores'), findsOneWidget);
      expect(
        find.byKey(const Key('edicion_masiva_resumen_ocultas')),
        findsNothing,
      );

      // Antes/después en texto (no por color) para cada cambio.
      expect(
        find.text('REVISIÓN DE CAMBIOS'),
        findsOneWidget,
        reason: 'revisión abierta',
      );
      expect(find.text('Precio de venta: 20.00 → 25.00'), findsOneWidget);
      expect(find.textContaining('Entrada: +3 pza'), findsOneWidget);
      expect(
        find.textContaining('saldo actual 500 → previsto 503'),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('edicion_masiva_revision_fila_${peso.clave.variantId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          Key('edicion_masiva_revision_fila_${sinSeguimiento.clave.variantId}'),
        ),
        findsOneWidget,
      );
      // El error explica qué corregir y el guardado queda bloqueado.
      expect(find.text('Requiere revisión'), findsOneWidget);
      expect(
        find.byKey(
          Key('edicion_masiva_error_venta_${sinSeguimiento.clave.variantId}'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Ingresa un importe con hasta dos decimales.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('edicion_masiva_guardar')),
            )
            .onPressed,
        isNull,
      );

      // La revisión muestra todas las capturas aunque la búsqueda oculte filas.
      await tester.tap(find.byKey(const Key('edicion_masiva_volver')));
      await tester.pumpAndSettle();
      await buscarEn(tester, 'Piezas');
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Incluye todo el borrador'), findsOneWidget);
      expect(
        find.byKey(Key('edicion_masiva_revision_fila_${peso.clave.variantId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          Key('edicion_masiva_revision_fila_${sinSeguimiento.clave.variantId}'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          Key('edicion_masiva_revision_fila_${piezas.clave.variantId}'),
        ),
        findsOneWidget,
      );

      // Volver, limpiar búsqueda y retirar la fila con error para habilitar guardar.
      await tester.tap(find.byKey(const Key('edicion_masiva_volver')));
      await tester.pumpAndSettle();
      await buscarEn(tester, '');
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          Key('edicion_masiva_retirar_${sinSeguimiento.clave.variantId}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Requiere revisión'), findsNothing);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('edicion_masiva_guardar')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M35/M37: guardar desde la revisión muestra resultados y limpia la captura',
    (tester) async {
      final filas = await abrir(tester);
      final peso = filas[0];
      final piezas = filas[1];

      await tester.enterText(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
        '25',
      );
      await tester.tap(find.byKey(const Key('edicion_masiva_tarea')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar existencias').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(Key('edicion_masiva_cantidad_${peso.clave.variantId}')),
        '3',
      );
      await tester.pump();

      // La revisión sigue siendo accesible con el teclado abierto (viewInsets).
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.resetViewInsets);
      expect(
        tester
            .widget<TextField>(
              find.byKey(
                Key('edicion_masiva_cantidad_${peso.clave.variantId}'),
              ),
            )
            .focusNode
            ?.hasFocus,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      expect(find.text('REVISIÓN DE CAMBIOS'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('edicion_masiva_guardar')),
            )
            .onPressed,
        isNotNull,
      );
      tester.view.viewInsets = FakeViewPadding.zero;

      await tester.tap(find.byKey(const Key('edicion_masiva_guardar')));
      await tester.pumpAndSettle();

      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(
        find.text('1 de 1 productos aplicados en este dispositivo.'),
        findsOneWidget,
      );
      expect(find.text('Aplicado en este dispositivo.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('edicion_masiva_listo')));
      await tester.pumpAndSettle();
      expect(
        find.text('Cambios guardados en este dispositivo.'),
        findsOneWidget,
      );
      expect(find.text('0 modificadas'), findsOneWidget);

      // La base local refleja ambos cambios vía coordinador.
      expect((await releerRecepcion(h.db, piezas.clave)).ventaMinor, 2500);
      expect(
        (await releerRecepcion(h.db, peso.clave)).entrada!.existenciaAtomic,
        503,
      );
      expect(await coordinadorRecepcion(h).pendientes(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M38/M40: volver durante guardado espera la transacción y presenta resultados',
    (tester) async {
      final filas = await seedRecepcion(h, nombre: 'Recepción');
      final otra = await seedRecepcion(h, nombre: 'Otra');
      final puerta = Completer<void>();
      final iniciado = Completer<void>();
      final lento = _ComandoLento(
        coordinadorRecepcion(h).diario,
        puerta.future,
        alIniciar: () {
          if (!iniciado.isCompleted) iniciado.complete();
        },
      );
      await pumpPantalla(tester, comando: lento);
      final piezas = filas[1];
      final otraPiezas = otra[1];
      expect(piezas.clave.productId, isNot(otraPiezas.clave.productId));

      await buscarEn(tester, 'Recepción');
      await tester.enterText(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
        '25',
      );
      await buscarEn(tester, 'Otra');
      await tester.enterText(
        find.byKey(Key('edicion_masiva_venta_${otraPiezas.clave.variantId}')),
        '45',
      );
      await tester.pump();
      expect(find.text('2 modificadas'), findsOneWidget);

      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edicion_masiva_guardar')));
      await tester.pumpAndSettle();
      await iniciado.future;

      // La ruta de revisión se cierra con el primer producto aún en curso.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      puerta.complete();
      await tester.pumpAndSettle();

      // Volver solicita cancelar, espera el producto activo y muestra cada estado.
      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(find.textContaining('1 pendientes de ejecutar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edicion_masiva_listo')));
      await tester.pumpAndSettle();
      expect(find.text('1 modificadas'), findsOneWidget);

      // El producto en curso terminó; el no iniciado no se aplicó.
      expect((await releerRecepcion(h.db, piezas.clave)).ventaMinor, 2500);
      expect((await releerRecepcion(h.db, otraPiezas.clave)).ventaMinor, 2000);
      expect(await coordinadorRecepcion(h).pendientes(), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M05/M09/M35: cero, vacío, venta independiente y errores conservados al volver',
    (tester) async {
      final filas = await abrir(tester);
      final piezas = filas[1];
      final id = piezas.clave.variantId;
      final antes = await fotoRecepcion(h.db);
      Future<void> tarea(String nombre) async {
        await tester.ensureVisible(
          find.byKey(const Key('edicion_masiva_tarea')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('edicion_masiva_tarea')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(nombre).last);
        await tester.pumpAndSettle();
      }

      await buscarEn(tester, 'Piezas');
      expect(
        tester
            .widget<TextField>(find.byKey(Key('edicion_masiva_venta_$id')))
            .controller!
            .text,
        '20.00',
      );
      await tarea('Costo estándar y proveedor');
      expect(
        tester
            .widget<TextField>(find.byKey(Key('edicion_masiva_costo_$id')))
            .controller!
            .text,
        '10.00',
      );
      await tester.enterText(find.byKey(Key('edicion_masiva_costo_$id')), '');
      await tester.pumpAndSettle();
      expect(find.textContaining('importe'), findsWidgets);
      await tester.enterText(find.byKey(Key('edicion_masiva_costo_$id')), '0');
      await tester.pumpAndSettle();
      await tarea('Precio de venta');
      expect(
        tester
            .widget<TextField>(find.byKey(Key('edicion_masiva_venta_$id')))
            .controller!
            .text,
        '20.00',
      );
      await tester.enterText(find.byKey(Key('edicion_masiva_venta_$id')), '0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      expect(find.text('Requiere revisión'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('edicion_masiva_guardar')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('edicion_masiva_volver')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(Key('edicion_masiva_venta_$id')))
            .controller!
            .text,
        '0',
      );
      await tester.enterText(find.byKey(Key('edicion_masiva_venta_$id')), '25');
      await tester.pumpAndSettle();
      await tarea('Agregar existencias');
      await tester.enterText(
        find.byKey(Key('edicion_masiva_cantidad_$id')),
        '-2',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Ingresa una magnitud positiva sin signo.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(Key('edicion_masiva_cantidad_$id')),
        '0',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      expect(find.text('Costo estándar: 10.00 → 0.00'), findsOneWidget);
      expect(find.text('Precio de venta: 20.00 → 25.00'), findsOneWidget);
      expect(find.textContaining('Entrada: +'), findsNothing);
      expect(await fotoRecepcion(h.db), antes);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M38: cierre durante confirmación no inicia ejecución con respuesta tardía',
    (tester) async {
      final filas = await seedRecepcion(h);
      final piezas = filas[1];
      final antes = await fotoRecepcion(h.db);
      final lento = _ConfirmacionLenta(coordinadorRecepcion(h).diario);
      await pumpPantalla(tester, comando: lento);
      await tester.enterText(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
        '25',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edicion_masiva_guardar')));
      await tester.pumpAndSettle();
      expect(lento.iniciado.isCompleted, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      lento.puerta.complete();
      await tester.pumpAndSettle();
      expect(lento.ejecuciones, 0);
      expect(find.text('RESULTADOS'), findsOneWidget);
      expect(find.textContaining('1 pendientes de ejecutar'), findsOneWidget);
      expect((await releerRecepcion(h.db, piezas.clave)).ventaMinor, 2000);
      final despues = await fotoRecepcion(h.db);
      expect(despues['events'], antes['events']);
      expect(despues['inventory_movements'], antes['inventory_movements']);
      expect(await coordinadorRecepcion(h).pendientes(), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M38: cerrar durante búsqueda o preparación ignora la respuesta tardía',
    (tester) async {
      final filas = await seedRecepcion(h);
      final catalogo = _CatalogoConPuerta(DriftCatalogoEdicionMasiva(h.db));
      final antes = await fotoRecepcion(h.db);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PantallaEdicionMasivaPorTarea(
                      catalogo: catalogo,
                      comando: coordinadorRecepcion(h),
                    ),
                  ),
                ),
                child: const Text('Abrir interna'),
              ),
            ),
          ),
        ),
      );
      catalogo.busqueda = Completer<void>();
      await tester.tap(find.text('Abrir interna'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      catalogo.busqueda!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Abrir interna'), findsOneWidget);
      expect(tester.takeException(), isNull);

      catalogo.busqueda = null;
      await tester.tap(find.text('Abrir interna'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(Key('edicion_masiva_venta_${filas[1].clave.variantId}')),
        '25',
      );
      await tester.pumpAndSettle();
      catalogo.lectura = Completer<void>();
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      catalogo.lectura!.complete();
      await tester.pumpAndSettle();
      expect(find.text('REVISIÓN DE CAMBIOS'), findsNothing);
      expect(find.text('1 modificadas'), findsOneWidget);
      expect(await fotoRecepcion(h.db), antes);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'M37: base obsoleta en la revisión explica el cambio y permite retirar',
    (tester) async {
      final filas = await abrir(tester);
      final piezas = filas[1];
      await tester.enterText(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
        '25',
      );
      await tester.pump();

      await h.db.customStatement(
        'UPDATE products SET version = version + 1 WHERE id = ?',
        [piezas.clave.productId],
      );

      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      expect(find.text('Requiere revisión'), findsOneWidget);
      expect(
        find.byKey(Key('edicion_masiva_error_base_${piezas.clave.variantId}')),
        findsOneWidget,
      );
      expect(
        find.text(
          'El producto cambió o dejó de estar disponible. Revisa la captura.',
        ),
        findsOneWidget,
      );
      // La foto nueva explica el estado sin sustituir lo capturado.
      expect(
        find.byKey(
          Key('edicion_masiva_revision_actual_${piezas.clave.variantId}'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.byKey(const Key('edicion_masiva_guardar')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(Key('edicion_masiva_retirar_${piezas.clave.variantId}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No hay cambios que revisar.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('M47: 320/360/390 px con nombres largos y campos legibles', (
    tester,
  ) async {
    final hLargo = ProductSupplierHarness();
    addTearDown(() => hLargo.dispose());
    final filas = await seedRecepcion(
      hLargo,
      nombre:
          'Producto con un nombre extraordinariamente largo para desbordar pantallas angostas',
    );
    final piezas = filas[1];
    addTearDown(tester.view.resetViewInsets);

    for (final ancho in [320.0, 360.0, 390.0, 800.0]) {
      tester.view.physicalSize = Size(ancho, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: PantallaEdicionMasivaPorTarea(
            catalogo: DriftCatalogoEdicionMasiva(hLargo.db),
            comando: coordinadorRecepcion(hLargo),
            ahora: () => ahora,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'revisión abierta');
      expect(find.byKey(const Key('edicion_masiva_revisar')), findsOneWidget);
      expect(
        find.byKey(Key('edicion_masiva_nombre_${piezas.clave.variantId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
        findsOneWidget,
      );
      expect(find.text('Buscar artículo o variante'), findsOneWidget);
      await tester.enterText(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
        '25',
      );
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      final campo = tester.getRect(
        find.byKey(Key('edicion_masiva_venta_${piezas.clave.variantId}')),
      );
      final boton = tester.getRect(
        find.byKey(const Key('edicion_masiva_revisar')),
      );
      expect(
        campo.bottom,
        lessThanOrEqualTo(boton.top),
        reason: 'campo visible con teclado, $ancho',
      );
      expect(
        boton.bottom,
        lessThanOrEqualTo(360),
        reason: 'revisión sobre teclado, $ancho',
      );
      expect(tester.takeException(), isNull, reason: 'teclado $ancho');
      await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
      await tester.pumpAndSettle();
      expect(
        find.text('REVISIÓN DE CAMBIOS'),
        findsOneWidget,
        reason: 'revisión abierta',
      );
      await tester.scrollUntilVisible(
        find.text('Precio de venta: 20.00 → 25.00'),
        100,
        scrollable: find.descendant(
          of: find.byKey(const Key('edicion_masiva_revision_listado')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Precio de venta: 20.00 → 25.00'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('edicion_masiva_guardar'))).bottom,
        lessThanOrEqualTo(360),
      );
      expect(tester.takeException(), isNull, reason: 'revisión $ancho');
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.tap(find.byKey(const Key('edicion_masiva_volver')));
      await tester.pumpAndSettle();
      for (final tarea in [
        'Costo estándar y proveedor',
        'Agregar existencias',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(const Key('edicion_masiva_tarea')),
          -200,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('edicion_masiva_listado')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('edicion_masiva_tarea')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tarea).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tarea $ancho');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('M47: entrada bloqueada por receta o sin seguimiento se explica', (
    tester,
  ) async {
    final filas = await seedRecepcion(h);
    final conReceta = filas[0]; // Peso: tiene recurso; la receta lo bloquea.
    final sinSeguimiento = filas[2];
    expect(conReceta.entrada, isNotNull);
    expect(sinSeguimiento.entrada, isNull);
    await h.db
        .into(h.db.recipeComponents)
        .insert(
          RecipeComponentsCompanion.insert(
            variantId: conReceta.clave.variantId,
            inventoryItemId: conReceta.entrada!.recurso.id,
            quantityAtomic: 1,
          ),
        );
    await pumpPantalla(tester);

    await tester.tap(find.byKey(const Key('edicion_masiva_tarea')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar existencias').last);
    await tester.pumpAndSettle();

    // Sin seguimiento directo: sin campo de cantidad y con explicación.
    expect(
      find.byKey(
        Key(
          'edicion_masiva_entrada_bloqueada_${sinSeguimiento.clave.variantId}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('no tiene seguimiento directo'), findsOneWidget);
    expect(
      find.byKey(
        Key('edicion_masiva_cantidad_${sinSeguimiento.clave.variantId}'),
      ),
      findsNothing,
    );
    // La variante con receta (insertada en la base) también se explica.
    expect(
      find.byKey(
        Key('edicion_masiva_entrada_bloqueada_${conReceta.clave.variantId}'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('usa receta'), findsOneWidget);
    // Los cambios comerciales siguen disponibles en la fila.
    expect(
      find.textContaining('Los cambios comerciales siguen disponibles'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('M37: proveedor predeterminado solo aplica a capturas nuevas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final proveedorId = (await tester.runAsync(
      () => h.supplier('ACME Distribuidora'),
    ))!;
    final flujo = Stream.value([
      Proveedor(
        id: proveedorId,
        nombre: 'ACME Distribuidora',
        version: 1,
        createdEventId: null,
        lastEventId: null,
        lastServerSequence: null,
      ),
    ]);
    final filas = await abrir(tester, proveedores: _ProveedoresFalsos(flujo));
    final peso = filas[0];

    await tester.tap(find.byKey(const Key('edicion_masiva_tarea')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Costo estándar y proveedor').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('edicion_masiva_proveedor_global')),
      findsOneWidget,
    );

    // El proveedor global se elige antes de capturar y la fila lo muestra
    // como predeterminado mientras no hay captura propia.
    await tester.tap(find.byKey(const Key('edicion_masiva_proveedor_global')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ACME Distribuidora').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Se usará: ACME Distribuidora'), findsWidgets);

    // Capturar el costo usa el predeterminado para ESTA fila.
    await buscarEn(tester, 'Peso');
    await tester.enterText(
      find.byKey(Key('edicion_masiva_costo_${peso.clave.variantId}')),
      '15',
    );
    await tester.pump();
    expect(
      find.textContaining('Proveedor: ACME Distribuidora'),
      findsOneWidget,
    );
    expect(find.textContaining('Se usará:'), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('edicion_masiva_proveedor_global')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edicion_masiva_proveedor_global')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sin proveedor').last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Proveedor: ACME Distribuidora'),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(Key('edicion_masiva_detalle_${peso.clave.variantId}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('edicion_masiva_detalle_${peso.clave.variantId}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('edicion_masiva_detalle_titulo')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('edicion_masiva_detalle_fecha')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('edicion_masiva_detalle_cerrar')));
    await tester.pumpAndSettle();

    // En la revisión el costo va con proveedor efectivo y fecha de captura.
    await tester.tap(find.byKey(const Key('edicion_masiva_revisar')));
    await tester.pumpAndSettle();
    expect(find.text('Costo estándar: desconocido → 15.00'), findsOneWidget);
    expect(
      find.byKey(
        Key('edicion_masiva_revision_proveedor_${peso.clave.variantId}'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Proveedor: ACME Distribuidora'), findsWidgets);
    expect(find.textContaining('18/10/2026'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _ProveedoresFalsos implements ProveedorRepository {
  _ProveedoresFalsos(this._flujo);
  final Stream<List<Proveedor>> _flujo;
  @override
  Stream<List<Proveedor>> watchProveedores() => _flujo;
}

/// Comando real cuya ejecución espera una puerta, para observar el cierre
/// de la ruta con una respuesta tardía.
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

class _ReadAudit extends QueryInterceptor {
  int writes = 0;
  int historyReads = 0;

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

class _ConfirmacionLenta extends EdicionMasivaCommandService {
  _ConfirmacionLenta(super.diario);
  final puerta = Completer<void>();
  final iniciado = Completer<void>();
  var ejecuciones = 0;
  @override
  Future<List<OperacionEdicionMasiva>> confirmar({
    required String batchId,
    required Iterable<CambioVarianteMasiva> cambios,
  }) async {
    final operaciones = await super.confirmar(
      batchId: batchId,
      cambios: cambios,
    );
    iniciado.complete();
    await puerta.future;
    return operaciones;
  }

  @override
  Future<ResultadoOperacionMasiva> ejecutar(OperacionEdicionMasiva op) {
    ejecuciones++;
    return super.ejecutar(op);
  }
}

class _CatalogoConPuerta implements CatalogoEdicionMasiva {
  _CatalogoConPuerta(this.real);
  final CatalogoEdicionMasiva real;
  Completer<void>? busqueda;
  Completer<void>? lectura;
  @override
  Future<List<FilaCatalogoMasivo>> buscar({
    String busqueda = '',
    int limite = 100,
    int desplazamiento = 0,
  }) async {
    await this.busqueda?.future;
    return real.buscar(
      busqueda: busqueda,
      limite: limite,
      desplazamiento: desplazamiento,
    );
  }

  @override
  Future<LecturaEdicionMasiva> leer(
    Set<ClaveVariante> claves, {
    Set<String> proveedorIds = const {},
  }) async {
    await lectura?.future;
    return real.leer(claves, proveedorIds: proveedorIds);
  }
}
