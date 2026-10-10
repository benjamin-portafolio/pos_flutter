import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/venta_borrador_event_handler.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/payloads/producto_agregado_borrador_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_producto_projection_store.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/articulos/variante_por_codigo_barras.dart';
import 'package:pos_flutter/domain/inventario/inventory_unit_ids.dart';
import 'package:pos_flutter/domain/ventas/sale_draft.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_product_selection_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_read_gate.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_barcode_scanner_screen.dart';

import '../../../support/fake_mobile_scanner_platform.dart';

void main() {
  late MobileScannerPlatform original;
  late FakeMobileScannerPlatform camera;
  late _Fixture fixture;
  late GlobalKey<NavigatorState> navigator;
  late Duration now;
  late BarcodeReadGate gate;

  setUp(() async {
    original = MobileScannerPlatform.instance;
    camera = FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = camera;
    MobileScannerController.resetPlatformSessionOwner();
    fixture = _Fixture();
    await fixture.seed();
    navigator = GlobalKey<NavigatorState>();
    now = Duration.zero;
    gate = BarcodeReadGate(clock: () => now);
  });
  tearDown(() async {
    await camera.captures.close();
    MobileScannerPlatform.instance = original;
    MobileScannerController.resetPlatformSessionOwner();
    await fixture.config.dispose();
  });

  void scannerTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        // Drift programa la cancelación del watch en un Timer de duración cero.
        // Desmontar y drenarlo antes de la comprobación final de Flutter.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(fixture.db.close);
        await tester.pump();
      }
    });
  }

  // El fake sustituye solo la cámara. Consulta, comando, evento, proyección y
  // watchCurrentDraft son reales; runAsync deja completar las consultas SQLite.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    bool fromCaja = false,
    int access = 0,
    Size size = const Size(360, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: fromCaja
              ? CajaScreen(
                  productoRepository: fixture.products,
                  saleDraftRepository: fixture.drafts,
                  ventaBorradorCommandService: fixture.commands,
                )
              : Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => SaleBarcodeScannerScreen(
                          productoRepository: fixture.products,
                          saleDraftRepository: fixture.drafts,
                          ventaBorradorCommandService: fixture.commands,
                          readGate: gate,
                        ),
                      ),
                    ),
                    child: const Text('Abrir lector'),
                  ),
                ),
        ),
      ),
    );
    await settle(tester);
    if (fromCaja) {
      final button = find.byTooltip('Escanear código de barras').at(access);
      await tester.ensureVisible(button);
      await tester.tap(button);
    } else {
      await tester.tap(find.text('Abrir lector'));
    }
    await settle(tester);
  }

  Future<void> emit(WidgetTester tester, List<String> codes) async {
    camera.captures.add(
      BarcodeCapture(
        barcodes: codes.map((code) => Barcode(rawValue: code)).toList(),
      ),
    );
    await tester.pump();
    await settle(tester);
  }

  Future<SaleDraft?> sale(WidgetTester tester) async => tester
      .runAsync<SaleDraft?>(() => fixture.drafts.watchCurrentDraft().first);

  Future<void> expectNoWrites(WidgetTester tester) async {
    await tester.runAsync(() async {
      expect(await fixture.db.select(fixture.db.events).get(), isEmpty);
      expect(await fixture.db.select(fixture.db.sales).get(), isEmpty);
      expect(await fixture.db.select(fixture.db.eventRefs).get(), isEmpty);
    });
  }

  for (final access in [0, 1]) {
    scannerTest(
      'acceso ${access + 1} de Caja abre una sola cámara, sin crear venta',
      (tester) async {
        await open(tester, fromCaja: true, access: access);
        expect(find.byType(SaleBarcodeScannerScreen), findsOneWidget);
        expect(find.byType(MobileScanner), findsOneWidget);
        expect(camera.starts, 1);
        expect(camera.lastStartOptions!.detectionSpeed, DetectionSpeed.normal);
        expect(camera.lastStartOptions!.detectionTimeoutMs, 200);
        expect(
          camera.lastStartOptions!.formats,
          isNot(contains(BarcodeFormat.qrCode)),
        );
        expect(camera.lastScanWindow, isNotNull);
        expect(camera.lastScanWindow!.width, lessThan(1));
        expect(camera.lastScanWindow!.height, lessThan(1));
        expect(find.text('La venta está vacía.'), findsOneWidget);
        expect(find.text('Ir a caja (0 artículos)'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('sale_barcode_go_to_caja')),
              )
              .onPressed,
          isNull,
        );
        await expectNoWrites(tester);
        await tester.tap(find.byKey(const Key('close_sale_barcode_scanner')));
        await settle(tester);
        expect(find.byType(CajaScreen), findsOneWidget);
        expect(camera.stops, 1);
        expect(camera.disposals, 1);
      },
    );
  }

  for (final mode in AppMode.values) {
    scannerTest(
      'venta previa, A → B → A, regreso y reapertura en ${mode.name}',
      (tester) async {
        await tester.runAsync(() async {
          fixture.config.update(AppConfig.initial.copyWith(mode: mode));
          await fixture.commands.agregar(
            const AgregarProductoBorradorCommand(variantId: 'A'),
          );
        });
        final previous = (await sale(tester))!;
        await open(tester, fromCaja: true);
        expect(find.text('Galletas'), findsOneWidget);
        expect(find.text(r'Precio: $1.00'), findsOneWidget);
        expect(find.text('Cantidad: 1'), findsOneWidget);
        expect(find.text(r'Total: $1.00'), findsOneWidget);
        await emit(tester, ['001']);
        await emit(tester, ['001']);
        await emit(tester, ['002']);
        await emit(tester, ['001']);
        expect(find.byType(SaleBarcodeScannerScreen), findsOneWidget);
        expect(find.text('Cantidad: 3'), findsOneWidget);
        expect(find.text('Entera'), findsOneWidget);
        expect(find.text(r'Total: $5.50'), findsOneWidget);
        expect(find.text('Ir a caja (2 artículos)'), findsOneWidget);
        await tester.tap(find.byKey(const Key('sale_barcode_go_to_caja')));
        await settle(tester);
        expect(find.byType(SaleBarcodeScannerScreen), findsNothing);
        expect(find.text(r'3 × $1.00'), findsOneWidget);
        expect(find.text(r'1 × $2.50'), findsOneWidget);
        expect(find.text(r'Cobrar: $5.50'), findsOneWidget);
        expect(find.text('2 artículos · 4 unidades'), findsOneWidget);
        final current = (await sale(tester))!;
        expect(current.id, previous.id);
        await tester.runAsync(() async {
          final events = await fixture.db.select(fixture.db.events).get();
          expect(events, hasLength(4));
          expect(
            events.every((event) => event.deliveryStatus == 'not_required'),
            isTrue,
          );
          expect(await fixture.db.eventDao.obtenerEventosPendientes(), isEmpty);
          for (final entry in fixture.events.entries) {
            final payload = ProductoAgregadoBorradorPayload.fromJson(
              entry.event.payload,
            );
            expect(
              entry.refs.map(
                (ref) => (ref.refType, ref.refId, ref.relationship),
              ),
              [
                ('sale', current.id, 'affects'),
                ('sale_item', payload.saleItemId, 'affects'),
                ('product', 'product-${payload.item.variantId}', 'uses'),
                ('product_variant', payload.item.variantId, 'uses'),
              ],
            );
          }
          expect(
            await fixture.db.select(fixture.db.eventRefs).get(),
            hasLength(mode == AppMode.standalone ? 0 : 16),
          );
          expect(await fixture.db.select(fixture.db.sales).get(), hasLength(1));
          expect(
            await fixture.db.select(fixture.db.inventoryMovements).get(),
            isEmpty,
          );
        });
        await tester.tap(find.byTooltip('Escanear código de barras').first);
        await settle(tester);
        expect(find.text(r'Total: $5.50'), findsOneWidget);
        await emit(tester, ['001']); // Reabrir no representa retirada.
        expect((await sale(tester))!.totalMinor, 550);
        await navigator.currentState!.maybePop();
        await settle(tester);
        expect(camera.disposals, 2);
      },
    );
  }

  scannerTest(
    '20 s de callbacks y tres presentaciones simuladas acumulan solo al rearmar',
    (tester) async {
      await open(tester);
      await emit(tester, [' ００１ ', '001']);
      for (var i = 1; i <= 100; i++) {
        now = Duration(milliseconds: i * 200);
        camera.captures.add(
          const BarcodeCapture(barcodes: [Barcode(rawValue: '001')]),
        );
        await tester.pump();
      }
      await settle(tester);
      expect(fixture.commands.attempts, hasLength(1));
      expect((await sale(tester))!.items.single.quantity, 1);
      for (var i = 0; i < 2; i++) {
        now += const Duration(
          milliseconds: 1100,
        ); // Silencio; no captura vacía ficticia.
        await emit(tester, ['001']);
        await emit(tester, ['001']);
      }
      expect((await sale(tester))!.items.single.quantity, 3);
      expect(find.text('Cantidad: 3'), findsOneWidget);
    },
  );

  for (final mode in AppMode.values) {
    scannerTest(
      'selección seguida de cantidad medida conserva evento y referencias en ${mode.name}',
      (tester) async {
        await tester.runAsync(() async {
          fixture.config.update(AppConfig.initial.copyWith(mode: mode));
          await (fixture.db.update(fixture.db.productVariants)
                ..where((v) => v.id.equals('M')))
              .write(const ProductVariantsCompanion(barcode: Value('003')));
        });
        await open(tester);
        await emit(tester, ['003']);
        expect(find.text(r'Medio · $200.00 / 1 kg'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('barcode_candidate_M')));
        await settle(tester);
        expect(find.byType(BarcodeProductSelectionDialog), findsNothing);
        expect(find.byType(SaleQuantityDialog), findsOneWidget);
        await tester.enterText(find.byType(TextField), '0.125');
        await tester.tap(find.text('Agregar'));
        await settle(tester);
        await emit(tester, ['003']);
        expect(fixture.commands.attempts, hasLength(1));
        expect(find.byType(BarcodeProductSelectionDialog), findsNothing);
        expect(find.byType(SaleQuantityDialog), findsNothing);
        expect(find.text(r'Total: $25.00'), findsOneWidget);
        await tester.runAsync(() async {
          final events = await fixture.db.select(fixture.db.events).get();
          expect(events, hasLength(1));
          expect(events.single.deliveryStatus, 'not_required');
          expect(
            fixture.events.entries.single.refs.map(
              (ref) => (ref.refType, ref.refId, ref.relationship),
            ),
            contains(('unit', InventoryUnitIds.kilogram, 'uses')),
          );
          expect(
            await fixture.db.select(fixture.db.eventRefs).get(),
            hasLength(mode == AppMode.standalone ? 0 : 5),
          );
          expect(await fixture.db.eventDao.obtenerEventosPendientes(), isEmpty);
        });
      },
    );
  }

  scannerTest('un fallo de detección detiene la cámara y conserva el regreso', (
    tester,
  ) async {
    await open(tester);
    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    scanner.onDetectError(StateError('Detector'), StackTrace.current);
    await settle(tester);
    expect(find.textContaining('Se interrumpió la cámara'), findsOneWidget);
    expect(camera.stops, 1);
    scanner.onDetect!(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '001')]),
    );
    expect(fixture.products.lookups, isEmpty);
    await tester.tap(find.byKey(const Key('close_sale_barcode_scanner')));
    await settle(tester);
    expect(camera.disposals, 1);
    await expectNoWrites(tester);
  });

  scannerTest(
    'desconocido, incompatible, varios códigos e inactivos no escriben',
    (tester) async {
      await open(tester);
      await emit(tester, ['999']);
      await emit(tester, ['999']);
      expect(
        find.text('No se encontró un artículo con este código.'),
        findsOneWidget,
      );
      expect(fixture.products.lookups, ['999']);
      await emit(tester, ['ABC']);
      await emit(tester, ['ABC']);
      expect(
        find.text('El código debe tener hasta 32 dígitos.'),
        findsOneWidget,
      );
      await emit(tester, ['001', '002']);
      expect(
        find.text('Enfoca un solo código dentro del marco.'),
        findsOneWidget,
      );
      await tester.runAsync(
        () => fixture.db.productoDao.actualizarProducto(
          'product-A',
          const ProductsCompanion(active: Value(false)),
        ),
      );
      await emit(tester, ['001']);
      expect(
        find.text('No se encontró un artículo con este código.'),
        findsOneWidget,
      );
      expect(fixture.commands.attempts, isEmpty);
      await expectNoWrites(tester);
    },
  );

  scannerTest(
    'código compartido selecciona producto, variante y precio sin primer resultado automático',
    (tester) async {
      await open(tester);
      await emit(tester, ['003']);
      expect(find.byType(BarcodeProductSelectionDialog), findsOneWidget);
      expect(find.text('Pan'), findsOneWidget);
      expect(find.text(r'Chico · $3.00'), findsOneWidget);
      expect(find.text('Bolillo'), findsOneWidget);
      expect(find.text(r'Grande · $4.00'), findsOneWidget);
      expect(fixture.commands.attempts, isEmpty);
      expect(camera.stops, 1);
      await tester.tap(find.byKey(const ValueKey('barcode_candidate_D')));
      await settle(tester);
      expect((await sale(tester))!.items.single.variantId, 'D');
      expect(find.text('Grande'), findsOneWidget);
      expect(find.text(r'Total: $4.00'), findsOneWidget);
      expect(camera.starts, 2);
      await emit(tester, ['003']);
      expect(fixture.commands.attempts, hasLength(1));
      expect(find.byType(BarcodeProductSelectionDialog), findsNothing);
    },
  );

  scannerTest(
    'cancelar selector y callbacks duplicados/ocultos no repiten el diálogo',
    (tester) async {
      await open(tester);
      final callback = tester
          .widget<MobileScanner>(find.byType(MobileScanner))
          .onDetect!;
      await emit(tester, ['003']);
      now += const Duration(minutes: 1);
      for (var i = 0; i < 10; i++) {
        callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '003')]));
      }
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      await emit(tester, ['003']);
      expect(fixture.products.lookups, ['003']);
      expect(find.byType(BarcodeProductSelectionDialog), findsNothing);
      await expectNoWrites(tester);
      now += const Duration(milliseconds: 1100);
      await emit(tester, ['003']);
      expect(find.byType(BarcodeProductSelectionDialog), findsOneWidget);
      await navigator.currentState!.maybePop();
      await settle(tester);
      await expectNoWrites(tester);
    },
  );

  scannerTest(
    'venta medida valida y convierte la cantidad con expectedUnitId',
    (tester) async {
      await open(tester);
      await emit(tester, ['004']);
      expect(find.byType(SaleQuantityDialog), findsOneWidget);
      expect(find.text('Café a granel · Medio'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('Agregar'));
      await tester.pump();
      expect(fixture.commands.attempts, isEmpty);
      await tester.enterText(find.byType(TextField), '0.750');
      await tester.tap(find.text('Agregar'));
      await settle(tester);
      final command = fixture.commands.attempts.single;
      expect(command.expectedUnitId, InventoryUnitIds.kilogram);
      expect(command.measuredQuantity, '0.750');
      final line = (await sale(tester))!.items.single;
      expect(line.measuredQuantityAtomic, 750);
      expect(line.quantity, isNull);
      expect(find.text('Cantidad: 0.750 kg'), findsOneWidget);
      expect(find.text(r'Precio: $200.00 / 1 kg'), findsOneWidget);
      expect(find.text(r'Total: $150.00'), findsOneWidget);
      await emit(tester, ['004']);
      expect(find.byType(SaleQuantityDialog), findsNothing);
    },
  );

  scannerTest(
    'cancelar cantidad y pausa del diálogo conservan la venta vacía',
    (tester) async {
      await open(tester);
      await emit(tester, ['004']);
      now += const Duration(minutes: 1);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      await emit(tester, ['004']);
      expect(fixture.products.lookups, ['004']);
      expect(find.byType(SaleQuantityDialog), findsNothing);
      expect(fixture.commands.attempts, isEmpty);
      await expectNoWrites(tester);
    },
  );

  scannerTest(
    'una unidad cambiada durante el diálogo falla sin una tarjeta optimista',
    (tester) async {
      await open(tester);
      await emit(tester, ['004']);
      await tester.runAsync(
        () => fixture.db.productoDao.actualizarProducto(
          'product-M',
          const ProductsCompanion(saleUnitId: Value(InventoryUnitIds.gram)),
        ),
      );
      await tester.enterText(find.byType(TextField), '0.750');
      await tester.tap(find.text('Agregar'));
      await settle(tester);
      expect(find.textContaining('La unidad de venta cambió'), findsOneWidget);
      expect(find.text('La venta está vacía.'), findsOneWidget);
      await expectNoWrites(tester);
      await emit(tester, ['004']);
      expect(find.byType(SaleQuantityDialog), findsNothing);
      expect(fixture.commands.attempts, hasLength(1));
    },
  );

  scannerTest(
    'segundo plano durante cantidad espera confirmación explícita al volver',
    (tester) async {
      await open(tester);
      await emit(tester, ['004']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      now += const Duration(minutes: 1);
      await emit(tester, ['004']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(fixture.commands.attempts, isEmpty);
      await expectNoWrites(tester);
      await tester.enterText(find.byType(TextField), '0.125');
      await tester.tap(find.text('Agregar'));
      await settle(tester);
      await emit(tester, ['004']);
      expect(fixture.commands.attempts, hasLength(1));
      expect((await sale(tester))!.items.single.measuredQuantityAtomic, 125);
      expect((await sale(tester))!.totalMinor, 2500);
    },
  );

  scannerTest('cancelar selector o cantidad conserva artículos previos', (
    tester,
  ) async {
    await tester.runAsync(
      () => fixture.commands.agregar(
        const AgregarProductoBorradorCommand(variantId: 'B'),
      ),
    );
    await open(tester);
    final before = (await sale(tester))!;
    for (final code in ['003', '004']) {
      await emit(tester, [code]);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      final after = (await sale(tester))!;
      expect(after.id, before.id);
      expect(after.items.single.id, before.items.single.id);
      expect(after.items.single.quantity, 1);
      expect(after.totalMinor, 250);
    }
    await tester.runAsync(() async {
      expect(await fixture.db.select(fixture.db.events).get(), hasLength(1));
    });
  });

  scannerTest(
    'unidad inactiva y variante retirada durante selección no escriben',
    (tester) async {
      await tester.runAsync(
        () =>
            (fixture.db.update(fixture.db.units)
                  ..where((u) => u.unitId.equals(InventoryUnitIds.kilogram)))
                .write(const UnitsCompanion(active: Value(false))),
      );
      await open(tester);
      await emit(tester, ['004']);
      expect(
        find.textContaining('La unidad de venta no está disponible'),
        findsOneWidget,
      );
      expect(find.byType(SaleQuantityDialog), findsNothing);
      await emit(tester, ['003']);
      await tester.runAsync(
        () =>
            (fixture.db.update(fixture.db.productVariants)
                  ..where((v) => v.id.equals('D')))
                .write(const ProductVariantsCompanion(active: Value(false))),
      );
      await tester.tap(find.byKey(const ValueKey('barcode_candidate_D')));
      await settle(tester);
      expect(find.text('La variante ya no está disponible.'), findsOneWidget);
      await expectNoWrites(tester);
    },
  );

  scannerTest(
    'fallo de consulta o guardado conserva venta previa y permite otra presentación',
    (tester) async {
      await tester.runAsync(
        () => fixture.commands.agregar(
          const AgregarProductoBorradorCommand(variantId: 'B'),
        ),
      );
      fixture.commands.attempts.clear();
      await open(tester);
      fixture.products.failure = Exception('Consulta');
      await emit(tester, ['001']);
      await emit(tester, ['001']);
      expect(fixture.products.lookups, ['001']);
      expect(find.textContaining('No se pudo agregar'), findsOneWidget);
      fixture.products.failure = null;
      fixture.commands.failure = Exception('Guardado');
      now += const Duration(milliseconds: 1100);
      await emit(tester, ['001']);
      await emit(tester, ['001']);
      expect(fixture.commands.attempts, hasLength(1));
      expect((await sale(tester))!.totalMinor, 250);
      expect(find.text(r'Total: $2.50'), findsOneWidget);
      fixture.commands.failure = null;
      now += const Duration(milliseconds: 1100);
      await emit(tester, ['001']);
      expect((await sale(tester))!.totalMinor, 350);
      expect(find.text(r'Total: $3.50'), findsOneWidget);
    },
  );

  scannerTest(
    'consulta y guardado lentos serializan admisión y observan presencia',
    (tester) async {
      fixture.products.lookupGate = Completer<void>();
      fixture.commands.saveGate = Completer<void>();
      await open(tester);
      await emit(tester, ['001']);
      await emit(tester, ['001']);
      expect(fixture.products.lookups, ['001']);
      expect(fixture.commands.attempts, isEmpty);
      fixture.products.lookupGate!.complete();
      await settle(tester);
      expect(fixture.commands.attempts, hasLength(1));
      for (var i = 1; i <= 15; i++) {
        now = Duration(milliseconds: i * 200);
        await emit(tester, ['001', '002']);
      }
      expect(find.text('La venta está vacía.'), findsOneWidget);
      expect(find.text('Guardando artículo…'), findsOneWidget);
      fixture.commands.saveGate!.complete();
      await settle(tester);
      await emit(tester, ['001']);
      expect(fixture.commands.attempts, hasLength(1));
      await emit(tester, ['002']);
      expect(fixture.commands.attempts, hasLength(2));
      expect((await sale(tester))!.totalMinor, 350);
    },
  );

  for (final systemBack in [false, true]) {
    scannerTest(
      'cerrar ${systemBack ? 'con regreso del sistema' : 'con botón'} espera el guardado y descarta callbacks antiguos',
      (tester) async {
        fixture.commands.saveGate = Completer<void>();
        await open(tester, fromCaja: true);
        final callback = tester
            .widget<MobileScanner>(find.byType(MobileScanner))
            .onDetect!;
        await emit(tester, ['001']);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('sale_barcode_go_to_caja')),
              )
              .onPressed,
          isNull,
        );
        if (systemBack) {
          await navigator.currentState!.maybePop();
        } else {
          await tester.tap(find.byKey(const Key('close_sale_barcode_scanner')));
        }
        await tester.pump();
        expect(
          find.text('Esperando la operación para cerrar…'),
          findsOneWidget,
        );
        callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '002')]));
        fixture.commands.saveGate!.complete();
        await settle(tester);
        expect(find.byType(SaleBarcodeScannerScreen), findsNothing);
        expect(find.text(r'Cobrar: $1.00'), findsOneWidget);
        expect((await sale(tester))!.items.single.quantity, 1);
        callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '002')]));
        await settle(tester);
        expect(fixture.commands.attempts, hasLength(1));
        expect(camera.stops, 1);
        expect(camera.disposals, 1);
      },
    );
  }

  scannerTest(
    'cerrar durante consulta descarta el resultado sin comenzar un guardado',
    (tester) async {
      fixture.products.lookupGate = Completer<void>();
      await open(tester);
      await emit(tester, ['003']);
      await tester.tap(find.byKey(const Key('close_sale_barcode_scanner')));
      await tester.pump();
      fixture.products.lookupGate!.complete();
      await settle(tester);
      expect(find.byType(SaleBarcodeScannerScreen), findsNothing);
      expect(find.byType(BarcodeProductSelectionDialog), findsNothing);
      expect(fixture.commands.attempts, isEmpty);
      await expectNoWrites(tester);
    },
  );

  scannerTest(
    'segundo plano y ruta cubierta no acreditan retirada ni aceptan callbacks',
    (tester) async {
      await open(tester);
      final callback = tester
          .widget<MobileScanner>(find.byType(MobileScanner))
          .onDetect!;
      await emit(tester, ['001']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      now += const Duration(minutes: 1);
      callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '002')]));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      await emit(tester, ['001']);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Otra ruta')),
          ),
        ),
      );
      await settle(tester);
      now += const Duration(minutes: 1);
      callback(const BarcodeCapture(barcodes: [Barcode(rawValue: '002')]));
      navigator.currentState!.pop();
      await settle(tester);
      await emit(tester, ['001']);
      expect(fixture.commands.attempts, hasLength(1));
      expect((await sale(tester))!.items.single.quantity, 1);
      expect(camera.starts, 3);
      expect(camera.stops, 2);
    },
  );

  for (final interruption in [
    'segundo plano',
    'pausa y regreso',
    'otra ruta',
  ]) {
    scannerTest(
      'consulta pendiente interrumpida por $interruption no agrega al terminar',
      (tester) async {
        fixture.products.lookupGate = Completer<void>();
        await open(tester);
        await emit(tester, ['001']);
        if (interruption == 'otra ruta') {
          unawaited(
            navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Otra ruta')),
              ),
            ),
          );
          await settle(tester);
          navigator.currentState!.pop();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await settle(tester);
          if (interruption == 'pausa y regreso') {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          }
        }
        await settle(tester);
        fixture.products.lookupGate!.complete();
        await settle(tester);
        expect(fixture.commands.attempts, isEmpty);
        await expectNoWrites(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await settle(tester);
        await emit(tester, ['001']); // Reanudar no acredita retirada.
        await expectNoWrites(tester);
        await emit(tester, ['002']);
        expect((await sale(tester))!.items.single.variantId, 'B');
      },
    );
  }

  scannerTest('segundo plano durante guardado conserva un solo commit', (
    tester,
  ) async {
    fixture.commands.saveGate = Completer<void>();
    await open(tester);
    await emit(tester, ['001']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);
    fixture.commands.saveGate!.complete();
    await settle(tester);
    expect((await sale(tester))!.items.single.quantity, 1);
    expect(camera.stops, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    await emit(tester, ['001']);
    expect(fixture.commands.attempts, hasLength(1));
  });

  for (final mode in AppMode.values) {
    scannerTest(
      'referencia vacía se valida antes de escribir en ${mode.name}',
      (tester) async {
        fixture.config.update(AppConfig.initial.copyWith(mode: mode));
        await tester.runAsync(() async {
          await fixture.db
              .into(fixture.db.products)
              .insert(
                ProductsCompanion.insert(id: ' ', name: 'Referencia inválida'),
              );
          await fixture.db
              .into(fixture.db.productVariants)
              .insert(
                ProductVariantsCompanion.insert(
                  id: 'bad-ref',
                  productId: ' ',
                  barcode: const Value('005'),
                  salePriceMinor: 100,
                  sortOrder: 0,
                ),
              );
        });
        await open(tester);
        await emit(tester, ['005']);
        expect(
          find.text('Las referencias y el contexto local son obligatorios.'),
          findsOneWidget,
        );
        expect(fixture.events.entries, isEmpty);
        await expectNoWrites(tester);
      },
    );

    scannerTest('A ×2 y B ×2, Caja y reinicio SQLite real en ${mode.name}', (
      tester,
    ) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('barcode-restart-'),
      ))!;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        paths,
        (_) async => directory.path,
      );
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths,
          null,
        );
        await directory.delete(recursive: true);
      });
      await tester.runAsync(() async {
        await fixture.db.close();
        await fixture.config.dispose();
        fixture = _Fixture(
          database: AppDatabase.forTesting(
            NativeDatabase(await appDatabaseFile()),
          ),
        );
        fixture.config.update(AppConfig.initial.copyWith(mode: mode));
        await fixture.seed();
      });
      await open(tester, fromCaja: true);
      for (final code in ['001', '002']) {
        await emit(tester, [code]);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1100)),
        );
        await emit(tester, [code]);
        await emit(tester, [code]);
      }
      expect((await sale(tester))?.totalMinor, 700);
      expect(find.text(r'Total: $7.00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sale_barcode_go_to_caja')));
      await settle(tester);
      expect(find.text('2 artículos · 4 unidades'), findsOneWidget);
      expect(find.text(r'Cobrar: $7.00'), findsOneWidget);
      final before = (await sale(tester))!;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      // Se recrean conexión SQLite, repositorios y pantalla sobre el archivo
      // temporal. barcode_draft_flow_test verifica además el arranque de
      // producción y su executor en otro isolate fuera del reloj de widgets.
      await tester.runAsync(() async {
        await fixture.db.close();
        await fixture.config.dispose();
        fixture = _Fixture(
          database: AppDatabase.forTesting(
            NativeDatabase(await appDatabaseFile()),
          ),
        );
        fixture.config.update(AppConfig.initial.copyWith(mode: mode));
      });
      await open(tester, fromCaja: true, access: 1);
      expect(find.text('Cantidad: 2'), findsNWidgets(2));
      expect(find.text(r'Total: $7.00'), findsOneWidget);
      final after = (await sale(tester))!;
      expect(after.id, before.id);
      expect(
        after.items.map((item) => item.id),
        before.items.map((item) => item.id),
      );
      expect(after.items.map((item) => item.quantity), [2, 2]);
      await tester.tap(find.byKey(const Key('sale_barcode_go_to_caja')));
      await settle(tester);
      expect(find.text(r'2 × $1.00'), findsOneWidget);
      expect(find.text(r'2 × $2.50'), findsOneWidget);
      await tester.runAsync(() async {
        final events = await fixture.db.select(fixture.db.events).get();
        expect(events, hasLength(4));
        expect(
          events.every((event) => event.deliveryStatus == 'not_required'),
          isTrue,
        );
        expect(
          await fixture.db.select(fixture.db.eventRefs).get(),
          hasLength(mode == AppMode.standalone ? 0 : 16),
        );
        fixture.config.update(
          AppConfig.initial.copyWith(mode: AppMode.serverSync),
        );
        expect(await fixture.db.eventDao.obtenerEventosPendientes(), isEmpty);
        expect(
          (await fixture.db.select(fixture.db.events).get()).every(
            (event) => event.deliveryStatus == 'not_required',
          ),
          isTrue,
        );
      });
    });

    scannerTest(
      'fallo SQLite durante proyección revierte evento, refs y venta en ${mode.name}',
      (tester) async {
        fixture.config.update(AppConfig.initial.copyWith(mode: mode));
        await tester.runAsync(
          () => fixture.db.customStatement(
            "CREATE TRIGGER reject_scan BEFORE INSERT ON sale_items BEGIN SELECT RAISE(ABORT, 'fallo de proyección'); END",
          ),
        );
        await open(tester);
        await emit(tester, ['001']);
        await emit(tester, ['001']);
        expect(find.textContaining('No se pudo agregar'), findsOneWidget);
        expect(fixture.commands.attempts, hasLength(1));
        await expectNoWrites(tester);
        await tester.runAsync(
          () => fixture.db.customStatement('DROP TRIGGER reject_scan'),
        );
        now += const Duration(milliseconds: 1100);
        await emit(tester, ['001']);
        expect((await sale(tester))!.items.single.quantity, 1);
        await tester.runAsync(() async {
          expect(
            await fixture.db.select(fixture.db.events).get(),
            hasLength(1),
          );
          expect(
            await fixture.db.select(fixture.db.eventRefs).get(),
            hasLength(mode == AppMode.standalone ? 0 : 4),
          );
        });
      },
    );
  }

  for (final error in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.unsupported,
  ]) {
    scannerTest(
      'cámara ${error.name} conserva productos previos y regreso disponible',
      (tester) async {
        await tester.runAsync(
          () => fixture.commands.agregar(
            const AgregarProductoBorradorCommand(variantId: 'A'),
          ),
        );
        camera.startError = MobileScannerException(errorCode: error);
        await open(tester, fromCaja: true);
        expect(
          find.byKey(const Key('sale_barcode_camera_error')),
          findsOneWidget,
        );
        expect(find.textContaining('buscador de Caja'), findsOneWidget);
        expect(find.text('Galletas'), findsOneWidget);
        await emit(tester, ['002']);
        expect(fixture.commands.attempts, hasLength(1));
        await tester.tap(find.byKey(const Key('sale_barcode_go_to_caja')));
        await settle(tester);
        expect(find.text(r'Cobrar: $1.00'), findsOneWidget);
        expect(camera.disposals, 1);
      },
    );
  }

  scannerTest(
    'permiso pendiente al cerrar libera la cámara cuando termina el inicio',
    (tester) async {
      camera.startGate = Completer<void>();
      await open(tester);
      await tester.tap(find.byKey(const Key('close_sale_barcode_scanner')));
      await settle(tester);
      expect(find.byType(SaleBarcodeScannerScreen), findsNothing);
      expect(camera.disposals, 0);
      camera.startGate!.complete();
      await settle(tester);
      expect(camera.stops, 1);
      expect(camera.disposals, 1);
      expect(tester.takeException(), isNull);
      await expectNoWrites(tester);
    },
  );

  scannerTest(
    'permiso pendiente al ir a segundo plano termina detenido y reanuda sin duplicar',
    (tester) async {
      camera.startGate = Completer<void>();
      await open(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      camera.startGate!.complete();
      await settle(tester);
      expect(camera.stops, 1);
      await emit(tester, ['001']);
      expect(fixture.commands.attempts, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      await emit(tester, ['001']);
      expect(fixture.commands.attempts, hasLength(1));
    },
  );

  scannerTest(
    'snapshots de precios distintos mantienen tarjetas distintas y un artículo',
    (tester) async {
      await open(tester);
      await emit(tester, ['001']);
      await tester.runAsync(
        () =>
            (fixture.db.update(
              fixture.db.productVariants,
            )..where((v) => v.id.equals('A'))).write(
              const ProductVariantsCompanion(salePriceMinor: Value(200)),
            ),
      );
      now += const Duration(milliseconds: 1100);
      await emit(tester, ['001']);
      final draft = (await sale(tester))!;
      expect(draft.items, hasLength(2));
      expect(draft.items.map((item) => item.unitPriceMinor), [100, 200]);
      expect(draft.articleCount, 1);
      expect(find.text(r'Precio: $1.00'), findsOneWidget);
      expect(find.text(r'Precio: $2.00'), findsOneWidget);
      expect(find.text('Ir a caja (1 artículo)'), findsOneWidget);
      expect(find.text(r'Total: $3.00'), findsOneWidget);
    },
  );

  scannerTest('snapshots de unidades distintas no se fusionan visualmente', (
    tester,
  ) async {
    await open(tester);
    await emit(tester, ['004']);
    await tester.enterText(find.byType(TextField), '0.750');
    await tester.tap(find.text('Agregar'));
    await settle(tester);
    await tester.runAsync(
      () => fixture.db.productoDao.actualizarProducto(
        'product-M',
        const ProductsCompanion(saleUnitId: Value(InventoryUnitIds.gram)),
      ),
    );
    // La primera observación después del diálogo establece la base activa.
    await emit(tester, ['004']);
    now += const Duration(milliseconds: 1100);
    await emit(tester, ['004']);
    await tester.enterText(find.byType(TextField), '750');
    await tester.tap(find.text('Agregar'));
    await settle(tester);
    final draft = (await sale(tester))!;
    expect(draft.items, hasLength(2));
    expect(draft.items.map((item) => item.unitSymbol), ['kg', 'g']);
    expect(find.text('Cantidad: 0.750 kg'), findsOneWidget);
    expect(find.text('Cantidad: 750 g'), findsOneWidget);
    expect(find.text('Ir a caja (1 artículo)'), findsOneWidget);
  });

  for (final sample in [
    (BarcodeFormat.ean13, '0012345678905'),
    (BarcodeFormat.ean8, '01234565'),
    (BarcodeFormat.upcA, '012345678905'),
  ]) {
    scannerTest(
      'callback ${sample.$1.name} conserva código y ceros iniciales',
      (tester) async {
        await tester.runAsync(
          () =>
              (fixture.db.update(fixture.db.productVariants)
                    ..where((v) => v.id.equals('A')))
                  .write(ProductVariantsCompanion(barcode: Value(sample.$2))),
        );
        await open(tester);
        expect(camera.lastStartOptions!.formats, contains(sample.$1));
        camera.captures.add(
          BarcodeCapture(
            barcodes: [Barcode(rawValue: sample.$2, format: sample.$1)],
          ),
        );
        await tester.pump();
        await settle(tester);
        expect(fixture.products.lookups, [sample.$2]);
        expect((await sale(tester))!.items.single.variantId, 'A');
        expect((await sale(tester))!.totalMinor, 100);
      },
    );
  }

  scannerTest(
    'rotar teléfono pequeño con texto ampliado conserva venta y controles',
    (tester) async {
      await tester.runAsync(
        () => fixture.commands.agregar(
          const AgregarProductoBorradorCommand(variantId: 'A'),
        ),
      );
      await open(tester, size: const Size(320, 640), textScale: 2);
      await emit(tester, ['999']);
      tester.view.physicalSize = const Size(640, 320);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(r'Total: $1.00'), findsOneWidget);
      await tester.ensureVisible(find.text('Cantidad: 1'));
      expect(find.text('Cantidad: 1').hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(const Key('sale_barcode_go_to_caja')));
      await settle(tester);
      expect((await sale(tester))!.items.single.quantity, 1);
      expect(find.byType(SaleBarcodeScannerScreen), findsNothing);
    },
  );

  for (final layout in [
    (const Size(320, 640), 2.0),
    (const Size(740, 360), 1.3),
    (const Size(1280, 800), 1.0),
  ]) {
    scannerTest(
      'tarjetas desplazables, cámara y total sin overflow en ${layout.$1}, texto ${layout.$2}',
      (tester) async {
        await tester.runAsync(() async {
          for (final id in ['A', 'B', 'C', 'D', 'M']) {
            await fixture.commands.agregar(
              AgregarProductoBorradorCommand(
                variantId: id,
                measuredQuantity: id == 'M' ? '0.750' : null,
                expectedUnitId: id == 'M' ? InventoryUnitIds.kilogram : null,
              ),
            );
          }
        });
        await open(tester, size: layout.$1, textScale: layout.$2);
        expect(find.text('Ir a caja (5 artículos)'), findsOneWidget);
        expect(find.text(r'Total: $160.50'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Cantidad: 0.750 kg'),
          100,
          scrollable: find
              .descendant(
                of:
                    find
                        .byKey(const Key('sale_barcode_compact_scroll'))
                        .evaluate()
                        .isNotEmpty
                    ? find.byKey(const Key('sale_barcode_compact_scroll'))
                    : find.byKey(const Key('sale_barcode_cards')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Cantidad: 0.750 kg'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('sale_barcode_go_to_caja')));
        await settle(tester);
        expect(find.byType(SaleBarcodeScannerScreen), findsNothing);
      },
    );
  }
}

class _Fixture {
  _Fixture({AppDatabase? database})
    : db = database ?? AppDatabase.forTesting(NativeDatabase.memory());
  final AppDatabase db;
  final config = AppConfigController(AppConfig.initial);
  late final products = _Products(productoDao: db.productoDao);
  late final drafts = SaleDraftRepositoryImpl(
    saleDao: db.saleDao,
    userId: 'user',
    deviceId: 'device',
  );
  late final commands = _Commands(
    store: db.saleDao,
    products: DriftProductoProjectionStore(productoDao: db.productoDao),
    units: UnidadInventarioRepositoryImpl(unitDao: db.unitDao),
    context: const LocalCommandContext(userId: 'user', deviceId: 'device'),
    events: events,
  );
  late final events = _RecordedLocalEvents(
    DriftLocalEventStore(
      db: db,
      eventDao: db.eventDao,
      eventRefDao: db.eventRefDao,
      appConfigController: config,
      eventProcessor: EventProcessor(
        handlers: {
          ProductoAgregadoBorradorPayload.eventType: VentaBorradorEventHandler(
            db.saleDao,
          ).apply,
        },
      ),
    ),
  );

  Future<void> seed() async {
    for (final data in [
      ('A', 'Galletas', null, '001', 100),
      ('B', 'Leche', 'Entera', '002', 250),
      ('C', 'Pan', 'Chico', '003', 300),
      ('D', 'Bolillo', 'Grande', '003', 400),
      ('M', 'Café a granel', 'Medio', '004', 20000),
    ]) {
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: 'product-${data.$1}',
              name: data.$2,
              saleMode: Value(data.$1 == 'M' ? 'measured' : 'unit'),
              saleUnitId: Value(
                data.$1 == 'M' ? InventoryUnitIds.kilogram : null,
              ),
              priceReferenceQuantityAtomic: Value(data.$1 == 'M' ? 1000 : null),
            ),
          );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: data.$1,
              productId: 'product-${data.$1}',
              name: Value(data.$3),
              nameKey: Value(data.$3?.toLowerCase()),
              barcode: Value(data.$4),
              salePriceMinor: data.$5,
              sortOrder: 0,
            ),
          );
    }
  }
}

/// Observa lo declarado por el comando sin sustituir transacción ni handler.
class _RecordedLocalEvents implements LocalEventStore {
  _RecordedLocalEvents(this.delegate);
  final LocalEventStore delegate;
  final entries = <LocalEventAppend>[];

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) {
    entries.add(LocalEventAppend(event: event, refs: refs));
    return delegate.appendAndApply(event, refs: refs);
  }
}

class _Products extends ProductoRepositoryImpl {
  _Products({required super.productoDao});
  final lookups = <String>[];
  Completer<void>? lookupGate;
  Exception? failure;

  @override
  Future<List<VariantePorCodigoBarras>> buscarVariantesPorCodigoBarras(
    String code,
  ) async {
    lookups.add(code);
    await lookupGate?.future;
    if (failure case final error?) throw error;
    return super.buscarVariantesPorCodigoBarras(code);
  }
}

class _Commands extends VentaBorradorCommandService {
  _Commands({
    required super.store,
    required super.products,
    required super.units,
    required super.context,
    required super.events,
  });
  final attempts = <AgregarProductoBorradorCommand>[];
  Completer<void>? saveGate;
  Exception? failure;

  @override
  Future<void> agregar(AgregarProductoBorradorCommand command) async {
    attempts.add(command);
    await saveGate?.future;
    if (failure case final error?) throw error;
    await super.agregar(command);
  }
}
