import 'dart:async';
import 'dart:io';
import 'dart:ui' show ViewFocusEvent, ViewFocusState, ViewFocusDirection;

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_flutter/application/commands/cotizaciones/cotizacion_command_service.dart';
import 'package:pos_flutter/domain/repositories/quotation_repository.dart';
import 'package:pos_flutter/data/repositories/quotation_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/presentation/pages/caja/draft_item_edit_sheet.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_barcode_scanner_screen.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotation_ticket_screen.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/domain/repositories/producto_repository.dart';
import 'package:pos_flutter/domain/repositories/sale_draft_repository.dart';
import 'package:pos_flutter/presentation/pages/articulos/article_search_screen.dart';
import 'package:pos_flutter/presentation/pages/articulos/sale_quantity_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/barcode/barcode_product_selection_dialog.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/home_screen.dart';

import '../../../support/barcode_sale_fixture.dart';
import '../../../support/quotation_harness.dart';
import '../../../support/pump_receipt_image.dart';
import '../../../support/fake_mobile_scanner_platform.dart';

void main() {
  late BarcodeSaleFixture f;
  late Directory directory;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    directory = await Directory.systemTemp.createTemp(
      'physical-barcode-widget-',
    );
    f = BarcodeSaleFixture(
      database: AppDatabase.forTesting(
        DatabaseConnection(
          NativeDatabase(File('${directory.path}/test.sqlite')),
          closeStreamsSynchronously: true,
        ),
      ),
    );
    await f.seed();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await f.dispose();
    await getIt.reset();
    await directory.delete(recursive: true);
  });

  Future<void> pumpCaja(
    WidgetTester tester, {
    bool home = false,
    CotizacionCommandService? quotes,
    QuotationRepository? quotations,
  }) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (home) {
      getIt.registerSingleton<SaleDraftRepository>(f.drafts);
      getIt.registerSingleton<ProductoRepository>(f.products);
      getIt.registerSingleton<VentaBorradorCommandService>(f.commands);
      getIt.registerSingleton<AppConfigController>(f.config);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: home
            ? const HomeScreen()
            : Scaffold(
                body: CajaScreen(
                  saleDraftRepository: f.drafts,
                  productoRepository: f.products,
                  ventaBorradorCommandService: f.commands,
                  cotizacionCommandService: quotes,
                  quotationRepository: quotations,
                  unidadInventarioRepository: UnidadInventarioRepositoryImpl(
                    unitDao: f.db.unitDao,
                  ),
                ),
              ),
      ),
    );
    await settle(tester);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
    });
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    for (final mode in AppMode.values) {
      readerTest(
        'activar una vez y Enter FIFO/repetidos en $platform ${mode.name}',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          f.config.update(AppConfig.initial.copyWith(mode: mode));
          await pumpCaja(tester);
          expect(find.byKey(inputKey), findsNothing);
          expect(tester.widget<Switch>(find.byKey(toggleKey)).value, isFalse);
          await enable(tester);
          expect(field(tester).focusNode!.hasFocus, isTrue);
          expect(find.textContaining('Listo para escanear'), findsOneWidget);
          final gate = Completer<void>();
          f.beforeSave = (_) =>
              f.attempts.length == 1 ? gate.future : Future.value();
          await send(tester, '001');
          await settle(tester);
          expect(find.textContaining('Guardando…'), findsWidgets);
          expect(find.textContaining('Agregado:'), findsNothing);
          await send(tester, '002');
          await send(tester, '001');
          await send(tester, '001');
          expect(field(tester).controller!.text, isEmpty);
          expect(field(tester).focusNode!.hasFocus, isTrue);
          await send(tester, '');
          await enter(tester);
          await tester.pump();
          expect(find.textContaining('3 lecturas pendientes'), findsOneWidget);
          gate.complete();
          await settle(tester);
          expect(f.lookups, ['001', '002', '001', '001']);
          expect(f.attempts.map((c) => c.variantId), ['A', 'B', 'A', 'A']);
          expect(find.text(r'3 × $1.00'), findsOneWidget);
          expect(find.text(r'Cobrar: $4.00'), findsOneWidget);
          expect(find.text('Agregado: A · 1 unidad'), findsOneWidget);
          final events = (await tester.runAsync(
            () => f.db.select(f.db.events).get(),
          ))!;
          expect(events, hasLength(4));
          expect(
            events.every((e) => e.deliveryStatus == 'not_required'),
            isTrue,
          );
          expect(
            (await tester.runAsync(() => f.db.select(f.db.eventRefs).get()))!,
            hasLength(mode == AppMode.serverSync ? 16 : 0),
          );
          expect(field(tester).focusNode!.hasFocus, isTrue);
          await tester.pumpWidget(const SizedBox.shrink());
          await settle(tester);
          await tester.runAsync(() async {
            await f.db.close();
            final reopened = AppDatabase.forTesting(
              NativeDatabase(File('${directory.path}/test.sqlite')),
            );
            try {
              final sale = await SaleDraftRepositoryImpl(
                saleDao: reopened.saleDao,
                userId: 'user',
                deviceId: 'device',
              ).watchCurrentDraft().first;
              expect(sale!.totalMinor, 400);
              expect(sale.items.map((i) => i.quantity), [3, 1]);
            } finally {
              await reopened.close();
            }
          });
        },
      );
    }
  }

  readerTest('vacío/repetido, inválidos íntegros, límite sin truncado y NFKC', (
    tester,
  ) async {
    await pumpCaja(tester);
    await enable(tester);
    for (final code in ['', '001A', 'A001', '00 1', '1' * 33]) {
      await send(tester, code);
    }
    expect(find.text('El código debe tener hasta 32 dígitos.'), findsOneWidget);
    expect(f.lookups, isEmpty);
    await send(tester, ' ００１ ');
    await settle(tester);
    await enter(tester);
    await settle(tester);
    expect(f.lookups, ['001']);
    expect(f.attempts, hasLength(1));
    await send(tester, '0' * 32);
    await settle(tester);
    expect(f.lookups.last, '0' * 32);
    expect(
      find.text('No se encontró un artículo con este código.'),
      findsOneWidget,
    );
    await send(tester, '002');
    await settle(tester);
    expect(find.text('Agregado: B · 1 unidad'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final cancel in [false, true]) {
    readerTest('selector propio conserva FIFO y foco, cancelar=$cancel', (
      tester,
    ) async {
      await pumpCaja(tester);
      await enable(tester);
      final query = Completer<void>();
      f.beforeLookup = (code) => code == '003' ? query.future : Future.value();
      await send(tester, '003');
      await send(tester, '001');
      query.complete();
      await settle(tester);
      expect(find.byType(BarcodeProductSelectionDialog), findsOneWidget);
      expect(f.attempts, isEmpty);
      await tester.tap(
        cancel
            ? find.text('Cancelar')
            : find.byKey(const ValueKey('barcode_candidate_D')),
      );
      await settle(tester);
      expect(f.attempts.map((c) => c.variantId), cancel ? ['A'] : ['D', 'A']);
      expect(field(tester).focusNode!.hasFocus, isTrue);
      await send(tester, '002');
      await settle(tester);
      expect(f.attempts.last.variantId, 'B');
    });
    readerTest('cantidad propia conserva cola y foco, cancelar=$cancel', (
      tester,
    ) async {
      await pumpCaja(tester);
      await enable(tester);
      final query = Completer<void>();
      f.beforeLookup = (code) => code == '004' ? query.future : Future.value();
      await send(tester, '004');
      await send(tester, '001');
      query.complete();
      await settle(tester);
      expect(find.byType(SaleQuantityDialog), findsOneWidget);
      if (!cancel) {
        await tester.enterText(
          find.descendant(
            of: find.byType(SaleQuantityDialog),
            matching: find.byType(TextField),
          ),
          '0.750',
        );
      }
      await tester.tap(find.text(cancel ? 'Cancelar' : 'Agregar'));
      await settle(tester);
      expect(f.attempts.map((c) => c.variantId), cancel ? ['A'] : ['M', 'A']);
      if (!cancel) expect(f.attempts.first.measuredQuantity, '0.750');
      expect(field(tester).focusNode!.hasFocus, isTrue);
    });
  }

  readerTest('error SQLite pausa y reanuda resto sin reintentar fallo', (
    tester,
  ) async {
    await tester.runAsync(
      () => f.db.customStatement(
        "CREATE TRIGGER reject_read BEFORE INSERT ON sale_items BEGIN SELECT RAISE(ABORT, 'fallo'); END",
      ),
    );
    await pumpCaja(tester);
    await enable(tester);
    final query = Completer<void>();
    f.beforeLookup = (code) => code == '001' ? query.future : Future.value();
    await send(tester, '001');
    await send(tester, '002');
    query.complete();
    await settle(tester);
    expect(
      find.textContaining('No se pudo agregar el artículo.'),
      findsOneWidget,
    );
    expect(find.textContaining('Agregado:'), findsNothing);
    expect(f.attempts, hasLength(1));
    await tester.runAsync(
      () => f.db.customStatement('DROP TRIGGER reject_read'),
    );
    await tester.tap(find.text('Reanudar lector'));
    await settle(tester);
    expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
    expect(find.text(r'Cobrar: $1.00'), findsOneWidget);
  });

  readerTest('Tab respeta foco de botones y permite reanudación', (
    tester,
  ) async {
    await pumpCaja(tester);
    await enable(tester);
    await tester.enterText(find.byKey(inputKey), '00');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(field(tester).focusNode!.hasFocus, isFalse);
    expect(field(tester).controller!.text, isEmpty);
    expect(find.textContaining('Lector en pausa'), findsOneWidget);
    await settle(tester);
    expect(field(tester).focusNode!.hasFocus, isFalse);
    await tester.tap(find.text('Reanudar lector'));
    await tester.pump();
    expect(field(tester).focusNode!.hasFocus, isTrue);
    await send(tester, '001');
    await settle(tester);
    expect(f.attempts, hasLength(1));
  });

  for (final window in [true, false]) {
    readerTest(
      'perder ${window ? "ventana" : "aplicación"} limpia y exige reanudación',
      (tester) async {
        await pumpCaja(tester);
        await enable(tester);
        await tester.enterText(find.byKey(inputKey), '00');
        if (window) {
          focusWindow(tester, false);
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        await tester.pump();
        expect(field(tester).controller!.text, isEmpty);
        if (window) {
          focusWindow(tester, true);
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pump();
        expect(find.textContaining('Lector en pausa'), findsOneWidget);
        await send(tester, '001');
        await settle(tester);
        expect(f.attempts, isEmpty);
        await tester.tap(find.text('Reanudar lector'));
        await tester.pump();
        await send(tester, '002');
        await settle(tester);
        expect(f.lookups, ['002']);
      },
    );
  }

  readerTest('búsqueda textual vuelve con modo/foco sin capturar en buscador', (
    tester,
  ) async {
    await pumpCaja(tester);
    await enable(tester);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Quiero vender…',
      ),
    );
    await settle(tester);
    expect(find.byType(ArticleSearchScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), '001');
    await enter(tester);
    await settle(tester);
    expect(f.attempts, isEmpty);
    await tester.pageBack();
    await settle(tester);
    expect(tester.widget<Switch>(find.byKey(toggleKey)).value, isTrue);
    expect(field(tester).focusNode!.hasFocus, isTrue);
    await send(tester, '001');
    await settle(tester);
    expect(f.attempts, hasLength(1));
  });

  readerTest('cobro drena cola y obtiene revisión/total actualizados', (
    tester,
  ) async {
    await tester.runAsync(
      () => f.commands.agregar(
        const AgregarProductoBorradorCommand(variantId: 'A'),
      ),
    );
    await pumpCaja(tester);
    await enable(tester);
    final save = Completer<void>();
    f.beforeSave = (_) => f.attempts.length == 2 ? save.future : Future.value();
    await send(tester, '002');
    await settle(tester);
    await send(tester, '001');
    await tester.tap(find.text(r'Cobrar: $1.00'));
    await tester.pump();
    expect(find.byType(PaymentMethodScreen), findsNothing);
    expect(find.text('Finalizando lecturas'), findsOneWidget);
    if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
      await tester.tap(find.text('Reanudar pendientes'));
    }
    save.complete();
    await settle(tester);
    final payment = tester.widget<PaymentMethodScreen>(
      find.byType(PaymentMethodScreen),
    );
    final draft = (await tester.runAsync(() => f.draft))!;
    expect(payment.totalMinor, 300);
    expect(payment.expectedDraftEventId, draft.lastEventId);
    expect(payment.saleId, draft.id);
    await tester.pageBack();
    await settle(tester);
    expect(field(tester).focusNode!.hasFocus, isTrue);
  });

  readerTest('desactivar drena; reactivar crea otra sesión', (tester) async {
    await pumpCaja(tester);
    await enable(tester);
    final gate = Completer<void>();
    f.beforeLookup = (code) => code == '001' ? gate.future : Future.value();
    await send(tester, '001');
    await send(tester, '002');
    await tester.tap(find.byKey(toggleKey));
    await tester.pump();
    expect(find.text('Finalizando lecturas'), findsOneWidget);
    if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
      await tester.tap(find.text('Reanudar pendientes'));
    }
    gate.complete();
    await settle(tester);
    expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
    expect(find.byKey(inputKey), findsNothing);
    await enable(tester);
    await send(tester, '001');
    await settle(tester);
    expect(f.attempts, hasLength(3));
  });

  readerTest(
    'Home espera guardado; descarte no deshace commit y regreso desactivado',
    (tester) async {
      await pumpCaja(tester, home: true);
      await enable(tester);
      final gate = Completer<void>();
      f.beforeSave = (_) => gate.future;
      await send(tester, '001');
      await settle(tester);
      await send(tester, '002');
      await tester.tap(find.text('Hoy'));
      await tester.pump();
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2,
      );
      await tester.tap(find.text('Descartar pendientes…'));
      await tester.pumpAndSettle();
      expect(find.text('Descartar 1 lecturas'), findsOneWidget);
      await tester.tap(find.text('Descartar 1 lecturas'));
      await tester.pump();
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2,
      );
      gate.complete();
      await settle(tester);
      expect(f.attempts.map((c) => c.variantId), ['A']);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        1,
      );
      await tester.tap(find.text('Caja'));
      await settle(tester);
      expect(tester.widget<Switch>(find.byKey(toggleKey)).value, isFalse);
      expect(find.byKey(inputKey), findsNothing);
      expect(find.text(r'Cobrar: $1.00'), findsOneWidget);
    },
  );

  readerTest(
    'menú espera consulta y descarte confirmado invalida respuestas tardías',
    (tester) async {
      await pumpCaja(tester, home: true);
      await enable(tester);
      final gate = Completer<void>();
      f.beforeLookup = (_) => gate.future;
      await send(tester, '003');
      await send(tester, '001');
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isFalse,
      );
      await tester.tap(find.text('Descartar pendientes…'));
      await tester.pumpAndSettle();
      expect(find.text('Descartar 2 lecturas'), findsOneWidget);
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Finalizando lecturas'), findsOneWidget);
      await tester.tap(find.text('Descartar pendientes…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar 2 lecturas'));
      await tester.pump();
      gate.complete();
      await settle(tester);
      expect(f.attempts, isEmpty);
      expect(find.byType(BarcodeProductSelectionDialog), findsNothing);
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await settle(tester);
      expect(tester.widget<Switch>(find.byKey(toggleKey)).value, isTrue);
    },
  );
  readerTest(
    'limpieza espera cola, elimina origen y nueva sesión no recibe lecturas viejas',
    (tester) async {
      await tester.runAsync(
        () => f.commands.agregar(
          const AgregarProductoBorradorCommand(variantId: 'A'),
        ),
      );
      final oldId = (await tester.runAsync(() => f.draft))!.id;
      await pumpCaja(tester);
      await enable(tester);
      final gate = Completer<void>();
      f.beforeSave = (_) =>
          f.attempts.length == 2 ? gate.future : Future.value();
      await send(tester, '001');
      await settle(tester);
      await send(tester, '002');
      await tester.tap(find.text('Limpiar venta'));
      await tester.pump();
      expect(find.text('Finalizando lecturas'), findsOneWidget);
      if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
        await tester.tap(find.text('Reanudar pendientes'));
      }
      gate.complete();
      await settle(tester);
      expect(await tester.runAsync(() => f.draft), isNull);
      expect(find.text('La venta está vacía.'), findsOneWidget);
      expect(field(tester).focusNode!.hasFocus, isTrue);
      await send(tester, '002');
      await settle(tester);
      final current = (await tester.runAsync(() => f.draft))!;
      expect(current.id, isNot(oldId));
      expect(current.items.single.variantId, 'B');
      expect(current.items.single.quantity, 1);
      expect(f.attempts.map((c) => c.variantId), ['A', 'A', 'B', 'B']);
    },
  );

  readerTest(
    'cotización guarda revisión drenada y nueva captura queda sin cola anterior',
    (tester) async {
      final quotation = QuotationHarness(database: f.db);
      addTearDown(quotation.config.dispose);
      final repository = QuotationRepositoryImpl(
        dao: f.db.quotationDao,
        validator: quotation.validator,
        userId: 'user',
        deviceId: 'device',
      );
      await tester.runAsync(
        () => f.commands.agregar(
          const AgregarProductoBorradorCommand(variantId: 'A'),
        ),
      );
      await pumpCaja(
        tester,
        quotes: quotation.service(owner: f.commands.context),
        quotations: repository,
      );
      await enable(tester);
      final gate = Completer<void>();
      f.beforeSave = (_) =>
          f.attempts.length == 2 ? gate.future : Future.value();
      await send(tester, '002');
      await settle(tester);
      await send(tester, '001');
      await tester.tap(find.text('Cotizar'));
      await tester.pump();
      expect(find.byType(QuotationTicketScreen), findsNothing);
      if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
        await tester.tap(find.text('Reanudar pendientes'));
      }
      gate.complete();
      await settle(tester);
      await pumpReceiptImage(tester);
      final ticket = tester.widget<QuotationTicketScreen>(
        find.byType(QuotationTicketScreen),
      );
      final draft = (await tester.runAsync(() => f.draft))!;
      expect(ticket.emissionDraft!.expectedDraftEventId, draft.lastEventId);
      final document = (await tester.runAsync(
        () => repository.findById(ticket.quotationId),
      ))!;
      expect(document.sourceDraftEventId, draft.lastEventId);
      expect(document.items.map((i) => i.quantity), [2, 1]);
      await tester.tap(find.text('Nueva captura'));
      await settle(tester);
      expect(await tester.runAsync(() => f.draft), isNull);
      expect(field(tester).focusNode!.hasFocus, isTrue);
      await send(tester, '002');
      await settle(tester);
      expect((await tester.runAsync(() => f.draft))!.items.single.quantity, 1);
    },
  );

  readerTest(
    'edición recibe cantidad posterior al drenaje y al cerrar recupera foco',
    (tester) async {
      await tester.runAsync(
        () => f.commands.agregar(
          const AgregarProductoBorradorCommand(variantId: 'A'),
        ),
      );
      await pumpCaja(tester);
      await enable(tester);
      final gate = Completer<void>();
      f.beforeSave = (_) => gate.future;
      await send(tester, '001');
      await settle(tester);
      await tester.tap(find.byTooltip('Editar artículo').first);
      await tester.pump();
      expect(find.byType(DraftItemEditSheet), findsNothing);
      if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
        await tester.tap(find.text('Reanudar pendientes'));
      }
      gate.complete();
      await settle(tester);
      expect(
        tester
            .widget<DraftItemEditSheet>(find.byType(DraftItemEditSheet))
            .item
            .quantity,
        2,
      );
      await tester.tap(find.byTooltip('Cerrar'));
      await settle(tester);
      expect(field(tester).focusNode!.hasFocus, isTrue);
    },
  );

  readerTest(
    'cámara espera lector, conserva contrato y regresar recupera modo/foco',
    (tester) async {
      final original = MobileScannerPlatform.instance;
      final camera = FakeMobileScannerPlatform();
      MobileScannerPlatform.instance = camera;
      MobileScannerController.resetPlatformSessionOwner();
      addTearDown(() async {
        MobileScannerPlatform.instance = original;
        MobileScannerController.resetPlatformSessionOwner();
        await camera.captures.close();
      });
      await pumpCaja(tester);
      await enable(tester);
      final gate = Completer<void>();
      f.beforeLookup = (_) => gate.future;
      await send(tester, '001');
      await tester.tap(find.byTooltip('Escanear código de barras').first);
      await tester.pump();
      expect(find.byType(SaleBarcodeScannerScreen), findsNothing);
      if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
        await tester.tap(find.text('Reanudar pendientes'));
      }
      gate.complete();
      await settle(tester);
      expect(find.byType(SaleBarcodeScannerScreen), findsOneWidget);
      expect(camera.starts, greaterThan(0));
      expect(f.attempts, hasLength(1));
      await tester.tap(find.byKey(const Key('close_sale_barcode_scanner')));
      await settle(tester);
      expect(field(tester).focusNode!.hasFocus, isTrue);
      await send(tester, '002');
      await settle(tester);
      expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
    },
  );

  readerTest(
    'finalizar con selector visible deja resolverlo y termina las otras lecturas',
    (tester) async {
      await pumpCaja(tester);
      await enable(tester);
      final gate = Completer<void>();
      f.beforeLookup = (_) => gate.future;
      await send(tester, '003');
      await send(tester, '001');
      gate.complete();
      await settle(tester);
      final caja = tester.state<CajaScreenState>(find.byType(CajaScreen));
      final leaving = caja.prepareToLeave();
      await tester.pump();
      expect(find.byType(BarcodeProductSelectionDialog), findsOneWidget);
      expect(find.text('Finalizando lecturas'), findsNothing);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(await leaving, isTrue);
      expect(f.attempts.map((c) => c.variantId), ['A']);
      expect(find.byKey(inputKey), findsNothing);
    },
  );

  readerTest('pausa externa durante cantidad no se reanuda al cerrar diálogo', (
    tester,
  ) async {
    await pumpCaja(tester);
    await enable(tester);
    await send(tester, '004');
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byType(SaleQuantityDialog),
        matching: find.byType(TextField),
      ),
      '0.500',
    );
    await tester.tap(find.text('Agregar'));
    await settle(tester);
    expect(f.attempts, isEmpty);
    expect(find.textContaining('Lector en pausa'), findsOneWidget);
    await tester.tap(find.text('Reanudar lector'));
    await settle(tester);
    expect(f.attempts.single.variantId, 'M');
    expect(f.attempts.single.measuredQuantity, '0.500');
  });

  readerTest('ruta externa congela consulta y volver exige reanudación', (
    tester,
  ) async {
    await pumpCaja(tester);
    await enable(tester);
    final gate = Completer<void>();
    f.beforeLookup = (_) => gate.future;
    await send(tester, '001');
    final navigator = Navigator.of(tester.element(find.byType(CajaScreen)));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Ruta externa')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    gate.complete();
    await settle(tester);
    expect(f.attempts, isEmpty);
    navigator.pop();
    await settle(tester);
    expect(find.textContaining('Lector en pausa'), findsOneWidget);
    await tester.tap(find.text('Reanudar lector'));
    await settle(tester);
    expect(f.attempts, hasLength(1));
  });

  readerTest(
    'error durante drenaje permite reanudar sin esperar indefinidamente',
    (tester) async {
      await tester.runAsync(
        () => f.commands.agregar(
          const AgregarProductoBorradorCommand(variantId: 'A'),
        ),
      );
      await pumpCaja(tester);
      await enable(tester);
      final gate = Completer<void>();
      f.beforeLookup = (code) => code == '002' ? gate.future : Future.value();
      f.beforeSave = (command) async {
        if (command.variantId == 'B') throw StateError('fallo de guardado');
      };
      await send(tester, '002');
      await send(tester, '001');
      await tester.tap(find.text(r'Cobrar: $1.00'));
      await tester.pump();
      if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
        await tester.tap(find.text('Reanudar pendientes'));
      }
      gate.complete();
      await settle(tester);
      expect(find.text('Finalizando lecturas'), findsOneWidget);
      expect(
        find.textContaining('La intención fallida no se reintentará.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Reanudar pendientes'));
      await settle(tester);
      final payment = tester.widget<PaymentMethodScreen>(
        find.byType(PaymentMethodScreen),
      );
      expect(payment.totalMinor, 200);
      expect(f.attempts.map((c) => c.variantId), ['A', 'B', 'A']);
    },
  );

  readerTest('fuera de macOS/Windows no se muestra modo lector', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpCaja(tester);
    expect(find.text('Lector físico'), findsNothing);
    expect(find.byKey(inputKey), findsNothing);
  });
  readerTest(
    'regreso de Home espera lecturas aceptadas antes de sacar la ruta',
    (tester) async {
      await pumpCaja(tester, home: true);
      final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        ),
      );
      await settle(tester);
      await enable(tester);
      final gate = Completer<void>();
      f.beforeSave = (_) => gate.future;
      await send(tester, '001');
      await settle(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Finalizando lecturas'), findsOneWidget);
      gate.complete();
      await settle(tester);
      expect(f.attempts, hasLength(1));
      expect(tester.widget<Switch>(find.byKey(toggleKey)).value, isFalse);
      expect(find.text(r'Cobrar: $1.00'), findsOneWidget);
    },
  );

  readerTest(
    'pérdida de ventana durante búsqueda conserva modo pausado al volver',
    (tester) async {
      await pumpCaja(tester);
      await enable(tester);
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == 'Quiero vender…',
        ),
      );
      await settle(tester);
      focusWindow(tester, false);
      await tester.pump();
      focusWindow(tester, true);
      await tester.pump();
      await tester.pageBack();
      await settle(tester);
      expect(tester.widget<Switch>(find.byKey(toggleKey)).value, isTrue);
      expect(find.textContaining('Lector en pausa'), findsOneWidget);
      await tester.tap(find.text('Reanudar lector'));
      await tester.pump();
      expect(field(tester).focusNode!.hasFocus, isTrue);
    },
  );
  readerTest(
    'cerrar menú sin navegar recupera modo y foco para otras lecturas',
    (tester) async {
      await pumpCaja(tester, home: true);
      await enable(tester);
      await tester.tap(find.byIcon(Icons.menu));
      await settle(tester);
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await settle(tester);
      expect(tester.widget<Switch>(find.byKey(toggleKey)).value, isTrue);
      expect(field(tester).focusNode!.hasFocus, isTrue);
      await send(tester, '001');
      await settle(tester);
      expect(f.attempts, hasLength(1));
    },
  );
  for (final committed in [false, true]) {
    readerTest(
      'error final del drenaje informa antes de cobrar, commit=$committed',
      (tester) async {
        await tester.runAsync(
          () => f.commands.agregar(
            const AgregarProductoBorradorCommand(variantId: 'A'),
          ),
        );
        await pumpCaja(tester);
        await enable(tester);
        final gate = Completer<void>();
        f.beforeLookup = (_) => gate.future;
        Future<void> fail(AgregarProductoBorradorCommand command) async {
          if (command.variantId == 'B') throw StateError('respuesta fallida');
        }

        if (committed) {
          f.afterSave = fail;
        } else {
          f.beforeSave = fail;
        }
        await send(tester, '002');
        await tester.tap(find.text(r'Cobrar: $1.00'));
        await tester.pump();
        if (find.text('Reanudar pendientes').evaluate().isNotEmpty) {
          await tester.tap(find.text('Reanudar pendientes'));
        }
        gate.complete();
        await settle(tester);
        expect(find.text('Error de lectura'), findsOneWidget);
        expect(find.byType(PaymentMethodScreen), findsNothing);
        expect(f.attempts.map((c) => c.variantId), ['A', 'B']);
        await tester.tap(find.text('Continuar'));
        await settle(tester);
        expect(
          tester
              .widget<PaymentMethodScreen>(find.byType(PaymentMethodScreen))
              .totalMinor,
          committed ? 200 : 100,
        );
        expect(f.attempts, hasLength(2));
      },
    );
  }
}

const inputKey = Key('physical_barcode_input');
const toggleKey = Key('physical_barcode_toggle');
TextField field(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(inputKey));
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> enable(WidgetTester tester) async {
  await tester.tap(find.byKey(toggleKey));
  await tester.pump();
  await tester.pump();
}

Future<void> send(WidgetTester tester, String code) async {
  // Simula escritura/pegado y la acción de edición que envía el engine.
  field(tester).controller!.text = code;
  await enter(tester);
  await tester.pump();
}

void focusWindow(WidgetTester tester, bool focused) {
  tester.binding.handleViewFocusChanged(
    ViewFocusEvent(
      viewId: tester.view.viewId,
      state: focused ? ViewFocusState.focused : ViewFocusState.unfocused,
      direction: ViewFocusDirection.undefined,
    ),
  );
}

Future<void> enter(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  // En tests el engine no traduce Enter a TextInputAction. Simular su acción
  // prueba onSubmitted sin invocar callbacks del widget directamente.
  await tester.testTextInput.receiveAction(TextInputAction.done);
}

void readerTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
