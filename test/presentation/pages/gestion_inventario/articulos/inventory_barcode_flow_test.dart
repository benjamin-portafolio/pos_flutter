import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/import/articulo_catalog_import_service.dart';
import 'package:pos_flutter/application/import/articulo_import_batch_service.dart';
import 'package:pos_flutter/application/sync/payloads/producto_actualizado_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/export/articulo_catalog_csv.dart';
import 'package:pos_flutter/data/local/import/articulo_import_csv.dart';
import 'package:pos_flutter/domain/articulos/articulo_listado.dart';
import 'package:pos_flutter/data/repositories/categoria_repository_impl.dart';
import 'package:pos_flutter/data/repositories/recurso_inventario_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/article_form_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/inventory_barcode_flow_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/inventory_barcode_assignment_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/inventory_barcode_variant_selector.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/inventory_management_screen.dart';

import '../../../../support/fake_mobile_scanner_platform.dart';
import '../../../../support/inventory_barcode_fixture.dart';

void main() {
  late MobileScannerPlatform original;
  late FakeMobileScannerPlatform camera;
  late InventoryBarcodeFixture f;
  late GlobalKey<NavigatorState> navigator;

  setUp(() async {
    original = MobileScannerPlatform.instance;
    camera = FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = camera;
    MobileScannerController.resetPlatformSessionOwner();
    f = InventoryBarcodeFixture();
    await f.seed();
    navigator = GlobalKey<NavigatorState>();
  });
  tearDown(() async {
    await camera.captures.close();
    MobileScannerPlatform.instance = original;
    MobileScannerController.resetPlatformSessionOwner();
  });

  void flowTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(f.h.dispose);
        await tester.pump();
      }
    });
  }

  Future<void> settle(WidgetTester tester) async {
    // Primero entregar callbacks de cámara/rutas, después drenar SQLite real.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool suppliers = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: InventoryManagementScreen(
          appConfigController: suppliers ? f.h.tracking.config : null,
          productoRepository: f.products,
          productoCommandService: f.commands,
          recursoInventarioRepository: RecursoInventarioRepositoryImpl(
            inventoryDao: f.h.db.inventoryDao,
          ),
          categoriaRepository: CategoriaRepositoryImpl(
            categoriaDao: f.h.db.categoriaDao,
          ),
          unidadInventarioRepository: UnidadInventarioRepositoryImpl(
            unitDao: f.h.db.unitDao,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> scan(WidgetTester tester, String code) async {
    await tester.tap(find.byKey(const Key('inventory_scan_barcode_button')));
    await tester.pumpAndSettle();
    camera.captures.add(BarcodeCapture(barcodes: [Barcode(rawValue: code)]));
    await settle(tester);
  }

  Future<void> selector(WidgetTester tester, [String code = '00042']) async {
    await open(tester);
    await scan(tester, code);
    expect(find.text('Código no encontrado'), findsOneWidget);
    await tester.tap(find.text('Asignar a una variante existente'));
    await settle(tester);
    expect(find.byType(InventoryBarcodeVariantSelector), findsOneWidget);
  }

  Future<void> target(
    WidgetTester tester,
    String product,
    String? variant,
  ) async {
    await tester.tap(
      find.byKey(
        ValueKey('inventory_barcode_target_${f.variant(product, variant)}'),
      ),
    );
    await settle(tester);
  }

  flowTest('lector sobre + solo en Artículos; + conserva su menú', (
    tester,
  ) async {
    await open(tester, suppliers: true);
    final reader = find.byKey(const Key('inventory_scan_barcode_button'));
    expect(
      tester.getCenter(reader).dy,
      lessThan(tester.getCenter(find.byTooltip('Agregar')).dy),
    );
    for (final tab in ['CATEGORÍA', 'RECURSOS', 'PROVEEDORES']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(reader, findsNothing);
    }
    await tester.tap(find.text('ARTÍCULOS'));
    await tester.pumpAndSettle();
    expect(reader, findsOneWidget);
    await tester.tap(find.byTooltip('Agregar'));
    await tester.pumpAndSettle();
    expect(find.text('Añadir artículo'), findsOneWidget);
  });

  flowTest(
    'una coincidencia abre edición ubicando la segunda variante, sin escribir',
    (tester) async {
      final before = await tester.runAsync(f.state);
      await open(tester);
      await scan(tester, '002');
      expect(find.text('EDITAR ARTÍCULO'), findsOneWidget);
      final form = tester.widget<ArticleFormScreen>(
        find.byType(ArticleFormScreen),
      );
      expect(form.initialVariantId, f.variant('Café', 'Grande'));
      expect(find.text('Variante escaneada'), findsOneWidget);
      expect(find.text('Variante escaneada').hitTestable(), findsOneWidget);
      expect(f.details, [f.article('Café').productoId]);
      await tester.tap(find.byTooltip('Cancelar'));
      await settle(tester);
      expect(find.byType(InventoryBarcodeFlowScreen), findsNothing);
      expect(await tester.runAsync(f.state), before);
    },
  );

  for (final cancel in [false, true]) {
    flowTest(
      'varias coincidencias requieren elección explícita, cancelar=$cancel',
      (tester) async {
        final before = await tester.runAsync(f.state);
        await open(tester);
        await scan(tester, '003');
        expect(find.text('Elegir coincidencia para editar'), findsOneWidget);
        expect(find.text('Variante sin nombre'), findsOneWidget);
        expect(find.text(r'$20.00'), findsOneWidget);
        expect(f.details, isEmpty);
        if (cancel) {
          await tester.tap(find.text('Cancelar'));
        } else {
          await tester.tap(
            find.byKey(
              ValueKey(
                'inventory_barcode_match_${f.variant('Leche', 'Entera')}',
              ),
            ),
          );
        }
        await settle(tester);
        if (!cancel) {
          expect(
            tester
                .widget<ArticleFormScreen>(find.byType(ArticleFormScreen))
                .initialVariantId,
            f.variant('Leche', 'Entera'),
          );
          await tester.tap(find.byTooltip('Cancelar'));
          await settle(tester);
        }
        expect(f.assignments, isEmpty);
        expect(await tester.runAsync(f.state), before);
      },
    );
  }

  flowTest(
    'búsqueda por artículo y variante, con/sin código y existencias; sin detalle por fila',
    (tester) async {
      await selector(tester);
      expect(find.byType(ListTile), findsNWidgets(6));
      expect(find.text('Variante sin nombre'), findsNWidgets(2));
      expect(f.details, isEmpty);
      await tester.enterText(
        find.byKey(const Key('inventory_barcode_search')),
        'café grande',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Grande'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('inventory_barcode_search')),
        'leche light',
      );
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      await target(tester, 'Leche', 'Light');
      expect(find.text('¿Asignar este código de barras?'), findsOneWidget);
      expect(f.details, [f.article('Leche').productoId]);
    },
  );

  for (final replace in [false, true]) {
    flowTest(
      'confirma ${replace ? 'reemplazo' : 'asignación'} y guarda localmente sin venta ni movimientos',
      (tester) async {
        final before = (await tester.runAsync(f.state))!;
        await selector(tester, ' ０００４２ ');
        await target(tester, 'Leche', replace ? 'Entera' : 'Light');
        expect(find.text('Código nuevo: 00042'), findsOneWidget);
        expect(
          find.text(
            replace
                ? '¿Reemplazar el código de barras?'
                : '¿Asignar este código de barras?',
          ),
          findsOneWidget,
        );
        if (replace) expect(find.text('Código actual: 003'), findsOneWidget);
        await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
        await settle(tester);
        expect(find.byType(InventoryBarcodeFlowScreen), findsNothing);
        expect(find.text('Código de barras guardado.'), findsOneWidget);
        expect(f.assignments, hasLength(1));
        final after = (await tester.runAsync(f.state))!;
        expect(after['events']!.length, f.initialEvents + 1);
        for (final table in [
          'sales',
          'sale_items',
          'inventory_movements',
          'inventory_items',
        ]) {
          expect(after[table], before[table], reason: table);
        }
        final matches = await tester.runAsync(
          () => f.h.repository.buscarVariantesPorCodigoBarras('00042'),
        );
        expect(
          matches!.single.varianteId,
          f.variant('Leche', replace ? 'Entera' : 'Light'),
        );
      },
    );
  }

  for (final mode in AppMode.values) {
    flowTest(
      'CSV sin barcode: asigna, reabre y reemplaza conservando coincidencias compartidas en ${mode.name}',
      (tester) async {
        final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('pos_inventory_barcode_'),
        );
        addTearDown(() => directory!.delete(recursive: true));
        final file = File('${directory!.path}/catalog.sqlite');
        InventoryBarcodeFixture connect() => InventoryBarcodeFixture(
          database: AppDatabase.forTesting(NativeDatabase(file)),
          mode: mode,
        );

        await tester.runAsync(() async {
          await f.h.dispose();
          f = connect();
          final units = UnidadInventarioRepositoryImpl(unitDao: f.h.db.unitDao);
          final report = const ArticuloImportCsv().validar(
            '${ArticuloCatalogCsv.columnasAnteriores.join(',')}\n'
            ',Café,unidad,,Chico,10.00,3.21,no,0,\n'
            ',Café,unidad,,Grande,15.00,4.56,si,7,\n'
            ',Agua,unidad,,,5.00,,no,0,\n',
            catalogo: ArticuloImportCatalogo(
              unidades: await units.obtenerUnidadesActivas(),
            ),
          );
          expect(report.errores, isEmpty);
          final imported = await ArticuloImportBatchService(
            productoCommandService: f.h.commands,
            unidadInventarioRepository: units,
          ).importar(report.productos, onProgress: (_) {});
          expect(imported.productosImportados, 2);
          expect(imported.lotesFallidos, isEmpty);
          f.articles = await f.h.repository.watchArticulos().first;
          expect(
            await f.h.db.select(f.h.db.productVariants).get(),
            everyElement(
              isA<ProductVariantRow>().having(
                (v) => v.barcode,
                'barcode importado',
                isNull,
              ),
            ),
          );
          await f.h.tracking.drafts.agregar(
            AgregarProductoBorradorCommand(
              variantId: f.variant('Café', 'Chico'),
            ),
          );
        });
        final selectedId = f.variant('Café', 'Grande');
        final otherId = f.variant('Café', 'Chico');

        Future<void> confirm(
          String rawCode,
          String normalizedCode, {
          String? previous,
        }) async {
          final before = (await tester.runAsync(f.state))!;
          await selector(tester, rawCode);
          expect(f.lookups.last, normalizedCode);
          await target(tester, 'Café', 'Grande');
          expect(find.text('Código nuevo: $normalizedCode'), findsOneWidget);
          expect(
            find.text(
              previous == null
                  ? '¿Asignar este código de barras?'
                  : '¿Reemplazar el código de barras?',
            ),
            findsOneWidget,
          );
          if (previous != null) {
            expect(find.text('Código actual: $previous'), findsOneWidget);
          }
          await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
          await settle(tester);
          expect(find.byType(InventoryBarcodeFlowScreen), findsNothing);
          expect(find.text('Código de barras guardado.'), findsOneWidget);
          final after = (await tester.runAsync(f.state))!;
          expect(after['events']!.length, before['events']!.length + 1);
          // Todas las demás tablas conservan incluso sus metadatos.
          for (final table in before.keys.where(
            (t) => !{
              'products',
              'product_variants',
              'events',
              'event_refs',
              'product_update_undo',
            }.contains(t),
          )) {
            expect(after[table], before[table], reason: table);
          }
          final append = f.h.appends.last;
          expect(append.event.eventType, ProductoActualizadoPayload.eventType);
          final payload = ProductoActualizadoPayload.fromJson(
            append.event.payload,
          );
          final expected = payload.before.toJson();
          final actual = payload.after.toJson();
          final changed = (actual['variants'] as List)
              .cast<Map<String, Object?>>()
              .singleWhere((v) => v['variant_id'] == selectedId);
          expect(changed['barcode'], normalizedCode);
          changed['barcode'] = previous;
          actual['dependencies'] = expected['dependencies'];
          expect(actual, expected);
          final stored = (await tester.runAsync(
            () => f.h.db.eventDao.obtenerEventoPorId(append.event.eventId),
          ))!;
          expect(stored.applicationStatus, 'applied');
          expect(
            stored.deliveryStatus,
            mode == AppMode.standalone ? 'not_required' : 'pending',
          );
          final refs = after['event_refs']!.where(
            (r) => r['event_id'] == stored.eventId,
          );
          expect(
            refs.length,
            mode == AppMode.standalone ? 0 : append.refs.length,
          );
          expect(append.refs, isNotEmpty);
        }

        Future<void> reopen() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          await tester.runAsync(() async {
            final saved = await f.state();
            await f.h.dispose();
            f = connect();
            f.articles = await f.h.repository.watchArticulos().first;
            expect(await f.state(), saved);
          });
        }

        Future<void> matches(String code, Set<String> expected) async {
          final found = await tester.runAsync(
            () => f.h.repository.buscarVariantesPorCodigoBarras(code),
          );
          expect(found!.map((v) => v.varianteId).toSet(), expected);
        }

        await confirm(' ０００４２ ', '00042');
        await reopen();
        await matches(' ０００４２ ', {selectedId});
        await matches('42', {});
        // La consulta posterior abre la edición real sin escribir por escanear.
        final saved = await tester.runAsync(f.state);
        await open(tester);
        await scan(tester, '00042');
        expect(
          tester
              .widget<ArticleFormScreen>(find.byType(ArticleFormScreen))
              .initialVariantId,
          selectedId,
        );
        await tester.tap(find.byTooltip('Cancelar'));
        await settle(tester);
        expect(await tester.runAsync(f.state), saved);

        // Compartir está permitido. Reemplazar Grande debe conservar Chico.
        await tester.runAsync(() => f.assignDirect('Café', 'Chico', '00042'));
        await matches('00042', {selectedId, otherId});
        await confirm('00043', '00043', previous: '00042');
        await reopen();
        await matches('00043', {selectedId});
        await matches('00042', {otherId});
        await matches('43', {});
      },
    );
  }

  for (final step in ['lector', 'aviso', 'selector', 'confirmación']) {
    flowTest('cancelar $step conserva todas las tablas', (tester) async {
      final before = await tester.runAsync(f.state);
      await open(tester);
      if (step == 'lector') {
        await tester.tap(
          find.byKey(const Key('inventory_scan_barcode_button')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
      } else {
        await scan(tester, '00042');
        if (step == 'aviso') {
          await tester.tap(find.text('Cancelar'));
        } else {
          await tester.tap(find.text('Asignar a una variante existente'));
          await settle(tester);
          if (step == 'selector') {
            await navigator.currentState!.maybePop();
          } else {
            await target(tester, 'Café', 'Grande');
            await tester.tap(find.text('Cancelar'));
          }
        }
      }
      await settle(tester);
      expect(find.byType(InventoryBarcodeFlowScreen), findsNothing);
      expect(await tester.runAsync(f.state), before);
    });
  }

  flowTest('base obsoleta recarga códigos y exige otra confirmación', (
    tester,
  ) async {
    await selector(tester);
    await target(tester, 'Café', 'Grande');
    final oldBase = (await tester.runAsync(
      () => f.h.repository.obtenerDetalle(f.article('Café').productoId),
    ))!.lastEventId;
    await tester.runAsync(() => f.assignDirect('Café', 'Grande', '009'));
    await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
    await settle(tester);
    expect(
      find.textContaining('El artículo cambió. Se recargaron'),
      findsOneWidget,
    );
    expect(find.text('Código actual: 009'), findsOneWidget);
    expect(find.text('Código nuevo: 00042'), findsOneWidget);
    expect(f.assignments.single.baseEventId, oldBase);
    expect(find.text('Código de barras guardado.'), findsNothing);
    await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
    await settle(tester);
    expect(f.assignments, hasLength(2));
    expect(f.assignments.last.baseEventId, isNot(oldBase));
    expect(find.text('Código de barras guardado.'), findsOneWidget);
  });

  flowTest(
    'asigna a variante sin nombre, sin barcode ni seguimiento de existencias',
    (tester) async {
      await selector(tester);
      await tester.enterText(
        find.byKey(const Key('inventory_barcode_search')),
        'agua',
      );
      await tester.pumpAndSettle();
      await target(tester, 'Agua', null);
      expect(find.text('Agua'), findsOneWidget);
      expect(find.text('Variante sin nombre'), findsOneWidget);
      expect(find.text('¿Asignar este código de barras?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
      await settle(tester);
      expect(f.assignments.single.variantId, f.variant('Agua', null));
      expect(find.text('Código de barras guardado.'), findsOneWidget);
    },
  );

  flowTest('fallo de guardado conserva selección/código y permite reintentar', (
    tester,
  ) async {
    await selector(tester);
    await target(tester, 'Café', 'Grande');
    f.h.failAfterProductApply = true;
    await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
    await settle(tester);
    expect(
      find.textContaining('No se pudo guardar el código.'),
      findsOneWidget,
    );
    expect(find.text('Código actual: 002'), findsOneWidget);
    expect(find.text('Código nuevo: 00042'), findsOneWidget);
    expect(
      (await tester.runAsync(f.state))!['events']!.length,
      f.initialEvents,
    );
    f.h.failAfterProductApply = false;
    await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
    await settle(tester);
    expect(find.text('Código de barras guardado.'), findsOneWidget);
  });

  flowTest('doble toque y salir durante guardado esperan un único comando', (
    tester,
  ) async {
    await selector(tester);
    await target(tester, 'Leche', 'Light');
    final gate = Completer<void>();
    f.beforeAssign = () => gate.future;
    final button = find.byKey(const Key('inventory_barcode_confirm'));
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(f.assignments, hasLength(1));
    expect(find.text('Guardando…'), findsOneWidget);
    await navigator.currentState!.maybePop();
    await tester.pump();
    expect(find.byType(InventoryBarcodeAssignmentScreen), findsOneWidget);
    expect(find.text('Código de barras guardado.'), findsNothing);
    gate.complete();
    await settle(tester);
    expect(find.text('Código de barras guardado.'), findsOneWidget);
  });

  flowTest('destino ya igual informa sin invocar comando', (tester) async {
    await selector(tester);
    await tester.runAsync(() => f.assignDirect('Leche', 'Light', '00042'));
    await target(tester, 'Leche', 'Light');
    expect(
      find.text('El código ya está asignado a esta variante.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Volver al inventario'));
    await settle(tester);
    expect(f.assignments, isEmpty);
  });

  flowTest('variante retirada entre confirmación y guardado se rechaza', (
    tester,
  ) async {
    await selector(tester);
    await target(tester, 'Leche', 'Light');
    await tester.runAsync(
      () =>
          (f.h.db.update(f.h.db.productVariants)
                ..where((v) => v.id.equals(f.variant('Leche', 'Light'))))
              .write(const ProductVariantsCompanion(active: Value(false))),
    );
    await tester.tap(find.byKey(const Key('inventory_barcode_confirm')));
    await settle(tester);
    expect(
      find.textContaining('ya no está disponible para asignar'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('inventory_barcode_confirm')), findsNothing);
    expect(find.text('Código nuevo: 00042'), findsOneWidget);
  });

  for (final code in ['texto-123', '123456789012345678901234567890123']) {
    flowTest(
      'código inválido $code permite reescanear sin consultar ni escribir',
      (tester) async {
        await open(tester);
        await scan(tester, code);
        expect(
          find.text('Solo admite dígitos, hasta 32 caracteres.'),
          findsOneWidget,
        );
        expect(f.lookups, isEmpty);
        expect(f.assignments, isEmpty);
        await tester.tap(find.text('Volver a escanear'));
        await tester.pumpAndSettle();
        camera.captures.add(
          const BarcodeCapture(barcodes: [Barcode(rawValue: '001')]),
        );
        await settle(tester);
        expect(find.text('EDITAR ARTÍCULO'), findsOneWidget);
      },
    );
  }

  flowTest(
    'lecturas vacías, repetidas y doble apertura producen una consulta',
    (tester) async {
      await open(tester);
      final button = find.byKey(const Key('inventory_scan_barcode_button'));
      final repeatOpen = tester.widget<FloatingActionButton>(button).onPressed!;
      await tester.tap(button);
      repeatOpen();
      await tester.pumpAndSettle();
      expect(camera.starts, 1);
      camera.captures.add(
        const BarcodeCapture(barcodes: [Barcode(rawValue: '  ')]),
      );
      await tester.pump();
      expect(f.lookups, isEmpty);
      camera.captures.add(
        const BarcodeCapture(barcodes: [Barcode(rawValue: '00042')]),
      );
      camera.captures.add(
        const BarcodeCapture(barcodes: [Barcode(rawValue: '001')]),
      );
      await settle(tester);
      expect(f.lookups, ['00042']);
      expect(camera.stops, 1);
      expect(camera.disposals, 1);
      expect(f.assignments, isEmpty);
    },
  );

  for (final error in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.unsupported,
  ]) {
    flowTest('cámara $error permite cancelar y reabrir', (tester) async {
      camera.startError = MobileScannerException(errorCode: error);
      await open(tester);
      await tester.tap(find.byKey(const Key('inventory_scan_barcode_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('barcode_scanner_error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
      await settle(tester);
      camera.startError = null;
      await scan(tester, '00042');
      expect(find.text('Código no encontrado'), findsOneWidget);
      expect(f.assignments, isEmpty);
    });
  }

  flowTest('segundo plano detiene cámara, ignora callback y permite reanudar', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('inventory_scan_barcode_button')));
    await tester.pumpAndSettle();
    final callback = tester
        .widget<MobileScanner>(find.byKey(const Key('barcode_scanner_camera')))
        .onDetect!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '001')]));
    expect(f.lookups, isEmpty);
    expect(camera.stops, greaterThanOrEqualTo(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.starts, 2);
    await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
    await settle(tester);
    callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '002')]));
    await settle(tester);
    expect(find.byType(InventoryBarcodeFlowScreen), findsNothing);
    expect(f.lookups, isEmpty);
    expect(camera.disposals, 1);
  });

  for (final close in [false, true]) {
    flowTest(
      'permiso pendiente al ${close ? 'cerrar' : 'pasar a segundo plano'} libera la cámara',
      (tester) async {
        final gate = Completer<void>();
        camera.startGate = gate;
        await open(tester);
        await tester.tap(
          find.byKey(const Key('inventory_scan_barcode_button')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(camera.starts, 1);
        if (close) {
          await tester.tap(
            find.byKey(const Key('close_barcode_scanner_button')),
          );
          await tester.pump(const Duration(milliseconds: 500));
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        }
        gate.complete();
        await settle(tester);
        expect(camera.stops, greaterThanOrEqualTo(1));
        expect(f.lookups, isEmpty);
        if (close) {
          expect(camera.disposals, 1);
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
          expect(camera.starts, 2);
          await tester.tap(
            find.byKey(const Key('close_barcode_scanner_button')),
          );
          await settle(tester);
        }
      },
    );
  }

  flowTest('consulta exacta tardía de una ruta cerrada no navega ni escribe', (
    tester,
  ) async {
    final gate = Completer<void>();
    f.beforeLookup = () => gate.future;
    await open(tester);
    await tester.tap(find.byKey(const Key('inventory_scan_barcode_button')));
    await tester.pumpAndSettle();
    camera.captures.add(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '001')]),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(f.lookups, ['001']);
    await navigator.currentState!.maybePop();
    await tester.pump(const Duration(milliseconds: 500));
    gate.complete();
    await settle(tester);
    expect(find.byType(ArticleFormScreen), findsNothing);
    expect(f.details, isEmpty);
    expect(f.assignments, isEmpty);
  });

  for (final assigning in [false, true]) {
    flowTest(
      'detalle tardío tras cerrar ${assigning ? 'confirmación' : 'edición'} no navega ni guarda',
      (tester) async {
        final gate = Completer<void>();
        if (assigning) {
          await selector(tester);
        } else {
          await open(tester);
          await tester.tap(
            find.byKey(const Key('inventory_scan_barcode_button')),
          );
          await tester.pumpAndSettle();
        }
        f.beforeDetail = () => gate.future;
        if (assigning) {
          await tester.tap(
            find.byKey(
              ValueKey(
                'inventory_barcode_target_${f.variant('Café', 'Chico')}',
              ),
            ),
          );
        } else {
          camera.captures.add(
            const BarcodeCapture(barcodes: [Barcode(rawValue: '001')]),
          );
        }
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        expect(f.details, hasLength(1));
        await navigator.currentState!.maybePop();
        await tester.pump(const Duration(milliseconds: 500));
        gate.complete();
        await settle(tester);
        expect(find.byType(ArticleFormScreen), findsNothing);
        expect(find.byType(InventoryBarcodeFlowScreen), findsNothing);
        expect(f.assignments, isEmpty);
      },
    );
  }

  flowTest('error de consulta conserva código y permite reintentar', (
    tester,
  ) async {
    f.beforeLookup = () async => throw StateError('fallo de lectura');
    await open(tester);
    await scan(tester, '00042');
    expect(find.text('Código: 00042'), findsOneWidget);
    expect(
      find.textContaining('No se pudo consultar el código.'),
      findsOneWidget,
    );
    f.beforeLookup = null;
    await tester.tap(find.text('Reintentar'));
    await settle(tester);
    expect(find.text('Código no encontrado'), findsOneWidget);
    expect(f.lookups, ['00042', '00042']);
  });

  flowTest('error de detalle conserva destino y código para recargar', (
    tester,
  ) async {
    await selector(tester);
    f.beforeDetail = () async => throw StateError('fallo de lectura');
    await target(tester, 'Leche', 'Light');
    expect(
      find.textContaining('No se pudo cargar el destino.'),
      findsOneWidget,
    );
    expect(find.text('Código nuevo: 00042'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    f.beforeDetail = null;
    await tester.tap(find.text('Recargar destino'));
    await settle(tester);
    expect(find.text('¿Asignar este código de barras?'), findsOneWidget);
    expect(f.assignments, isEmpty);
  });

  flowTest(
    'selector muestra carga, error con reintento, vacío y búsqueda sin resultados',
    (tester) async {
      await open(tester);
      await scan(tester, '00042');
      final stream = StreamController<List<ArticuloListado>>.broadcast();
      f.catalog = () => stream.stream;
      await tester.tap(find.text('Asignar a una variante existente'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      stream.addError(StateError('catálogo no disponible'));
      await tester.pumpAndSettle();
      expect(find.text('No se pudieron cargar los artículos.'), findsOneWidget);
      f.catalog = () => Stream.value(const []);
      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      expect(find.text('No hay variantes activas.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('inventory_barcode_search')),
        'inexistente',
      );
      await tester.pumpAndSettle();
      expect(find.text('No se encontraron variantes.'), findsOneWidget);
      await tester.runAsync(stream.close);
    },
  );
}
