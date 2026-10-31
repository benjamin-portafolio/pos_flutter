import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/cambiar_tarifa_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/application/commands/ventas/venta_command_service.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/offer_pricing_availability.dart';
import 'package:pos_flutter/application/sync/payloads/tarifa_venta_borrador_cambiada_payload.dart';
import 'package:pos_flutter/application/sync/sync_capability_store.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_confirmed_sale_store.dart';
import 'package:pos_flutter/data/local/drift/drift_inventory_projection_store.dart';
import 'package:pos_flutter/data/repositories/confirmed_sale_repository_impl.dart';
import 'package:pos_flutter/data/repositories/producto_repository_impl.dart';
import 'package:pos_flutter/data/repositories/sale_draft_repository_impl.dart';
import 'package:pos_flutter/data/repositories/unidad_inventario_repository_impl.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/presentation/pages/caja/caja_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/payment_method_screen.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';

import '../../../support/pump_receipt_image.dart';
import '../../../support/fake_mobile_scanner_platform.dart';
import '../../../support/quotation_harness.dart';

class _Capabilities extends SyncCapabilityStore {
  List<String>? capabilities = ['offer_pricing_v2'];
  @override
  Future<List<String>?> read(String endpoint) async => capabilities;
  @override
  Future<void> write(String endpoint, List<String> capabilities) async {
    this.capabilities = capabilities;
  }
}

class _Commands extends VentaBorradorCommandService {
  _Commands(
    QuotationHarness h,
    SaleDraftRepositoryImpl repository,
    _Capabilities capabilities,
  ) : super(
        store: h.db.saleDao,
        products: h.products,
        units: UnidadInventarioRepositoryImpl(unitDao: h.db.unitDao),
        events: h.events,
        context: h.context,
        drafts: repository,
        offerPricing: OfferPricingAvailability(
          config: h.config,
          endpoint: SyncEndpointConfig(initialBaseUrl: 'http://localhost:1'),
          store: capabilities,
        ),
      );
  final attempts = <CambiarTarifaVentaBorradorCommand>[];
  Future<void> Function()? beforeApply;
  bool failAfterApply = false;
  @override
  Future<TarifaVentaBorradorCambiadaPayload?> cambiarTarifa(
    CambiarTarifaVentaBorradorCommand command,
  ) async {
    attempts.add(command);
    await beforeApply?.call();
    final result = await super.cambiarTarifa(command);
    if (failAfterApply) throw StateError('Respuesta interrumpida');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontDir = Platform.environment['POS_OFFER_VISUAL_FONTS'];
    if (fontDir == null) return;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(
          File(
            '$fontDir/${entry.value}',
          ).readAsBytes().then((b) => ByteData.sublistView(b)),
        );
      await loader.load();
    }
  });
  late QuotationHarness h;
  late SaleDraftRepositoryImpl drafts;
  late _Commands commands;
  late _Capabilities capabilities;
  final boundary = GlobalKey();
  final toggle = find.byKey(const Key('sale_offer_toggle'));
  final confirm = find.byKey(const Key('confirm_sale_pricing'));

  void connect() {
    drafts = SaleDraftRepositoryImpl(
      saleDao: h.db.saleDao,
      userId: h.context.userId,
      deviceId: h.context.deviceId,
    );
    capabilities = _Capabilities();
    commands = _Commands(h, drafts, capabilities);
  }

  setUp(() async {
    h = QuotationHarness(mode: AppMode.serverSync);
    connect();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await getIt.reset();
    await h.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(420, 950),
    double textScale = 1,
    bool seed = true,
    bool physical = false,
  }) async {
    debugDefaultTargetPlatformOverride = physical
        ? TargetPlatform.android
        : TargetPlatform.iOS;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (seed) {
      await tester.runAsync(() async {
        await h.seed();
        await h.db.productoDao.actualizarVariante(
          QuotationHarness.directId,
          const ProductVariantsCompanion(offerPriceMinor: Value(2000)),
        );
      });
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Platform.environment['POS_OFFER_VISUAL_FONTS'] == null
              ? null
              : ThemeData(fontFamily: 'Roboto'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: CajaScreen(
              saleDraftRepository: drafts,
              ventaBorradorCommandService: commands,
              productoRepository: ProductoRepositoryImpl(
                productoDao: h.db.productoDao,
              ),
              unidadInventarioRepository: UnidadInventarioRepositoryImpl(
                unitDao: h.db.unitDao,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> add(
    WidgetTester tester, [
    String id = QuotationHarness.directId,
  ]) async {
    await tester.runAsync(
      () => commands.agregar(AgregarProductoBorradorCommand(variantId: id)),
    );
    await settle(tester);
  }

  Future<void> accept(WidgetTester tester) async {
    await tester.tap(toggle);
    await settle(tester);
    await tester.tap(confirm);
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['POS_OFFER_VISUAL_DIR'];
    if (directory == null) return;
    await tester.pump();
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
  }

  void check(String name, Future<void> Function(WidgetTester) body) {
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

  check(
    'vacía cambia inmediato, persiste modo, pestañas aisladas y nueva normal',
    (tester) async {
      await open(tester);
      final first = drafts.selectedDraftId;
      await tester.tap(toggle);
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Precio de oferta · Activo'), findsOneWidget);
      expect(commands.attempts.single.saleId, first);
      await add(tester);
      expect(find.text(r'Cobrar: $20.00'), findsOneWidget);
      expect(find.text('Oferta aplicada'), findsOneWidget);
      await tester.tap(find.text('Venta 2'));
      await settle(tester);
      expect(find.text('Precio de oferta · Normal'), findsOneWidget);
      await add(tester);
      expect(find.text(r'Cobrar: $35.00'), findsOneWidget);
      await tester.tap(find.text('Venta 1'));
      await settle(tester);
      expect(find.text(r'Cobrar: $20.00'), findsOneWidget);
      await tester.tap(find.byTooltip('Agregar venta'));
      await settle(tester);
      expect(find.text('Precio de oferta · Normal'), findsOneWidget);
    },
  );

  check(
    'mezcla confirma preview, cancelar no escribe, etiquetas y restauración capturada',
    (tester) async {
      await open(tester);
      await add(tester);
      await add(tester, QuotationHarness.recipeId);
      final before = await tester.runAsync(() => h.contents());
      await tester.tap(toggle);
      await settle(tester);
      expect(find.text('Tarifa actual: Normal'), findsOneWidget);
      expect(find.text('Tarifa nueva: Oferta'), findsOneWidget);
      expect(find.text('1 línea cambia de importe.'), findsOneWidget);
      expect(
        find.text('1 línea sin oferta conserva precio normal.'),
        findsOneWidget,
      );
      expect(find.text(r'Nuevo total: $44.00'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await settle(tester);
      expect(await tester.runAsync(() => h.contents()), before);
      expect(commands.attempts, isEmpty);
      await accept(tester);
      expect(find.text('Oferta aplicada'), findsOneWidget);
      expect(find.text('Precio normal · sin oferta capturada'), findsOneWidget);
      expect(find.text(r'Cobrar: $44.00'), findsOneWidget);
      await tester.runAsync(
        () => h.db.productoDao.actualizarVariante(
          QuotationHarness.directId,
          const ProductVariantsCompanion(
            salePriceMinor: Value(6000),
            offerPriceMinor: Value(3000),
          ),
        ),
      );
      await settle(tester);
      expect(find.text(r'Cobrar: $44.00'), findsOneWidget);
      await accept(tester);
      expect(find.text(r'Cobrar: $59.00'), findsOneWidget);
    },
  );

  check(
    'sin oferta no etiqueta líneas como oferta y precio igual acredita origen',
    (tester) async {
      await open(tester);
      await add(tester, QuotationHarness.recipeId);
      await accept(tester);
      expect(find.text('Precio normal · sin oferta capturada'), findsOneWidget);
      expect(find.text('Oferta aplicada'), findsNothing);
      expect(find.text(r'Cobrar: $24.00'), findsOneWidget);
      await tester.runAsync(
        () => h.db.productoDao.actualizarVariante(
          QuotationHarness.directId,
          const ProductVariantsCompanion(offerPriceMinor: Value(3500)),
        ),
      );
      await add(tester);
      expect(find.text('Oferta aplicada'), findsOneWidget);
      await tester.tap(toggle);
      await settle(tester);
      expect(
        find.text('1 línea cambia de tarifa sin cambiar de importe.'),
        findsOneWidget,
      );
      expect(find.text(r'Nuevo total: $59.00'), findsOneWidget);
      await tester.tap(confirm);
      await settle(tester);
      expect(find.text('Oferta aplicada'), findsNothing);
      expect(find.text(r'Cobrar: $59.00'), findsOneWidget);
    },
  );

  check('doble toque bloqueado y UI espera resultado del comando', (
    tester,
  ) async {
    await open(tester);
    await add(tester);
    final gate = Completer<void>();
    commands.beforeApply = () => gate.future;
    await tester.tap(toggle);
    await settle(tester);
    await tester.tap(confirm);
    await settle(tester);
    expect(commands.attempts, hasLength(1));
    expect(tester.widget<OutlinedButton>(toggle).onPressed, isNull);
    expect(find.text('Precio de oferta · Normal'), findsOneWidget);
    expect(find.text(r'Cobrar: $35.00'), findsOneWidget);
    gate.complete();
    await settle(tester);
    expect(find.text('Precio de oferta · Activo'), findsOneWidget);
  });

  check('preview obsoleto rechaza completo y recupera total persistido', (
    tester,
  ) async {
    await open(tester);
    await add(tester);
    await tester.tap(toggle);
    await settle(tester);
    await add(tester);
    await tester.tap(confirm);
    await settle(tester);
    expect(
      find.textContaining('No se pudo confirmar el cambio de tarifa.'),
      findsOneWidget,
    );
    expect(find.text('Precio de oferta · Normal'), findsOneWidget);
    await capture(tester, 'error-revision-420x950');
    expect(find.text(r'Cobrar: $70.00'), findsOneWidget);
    expect(find.text('Oferta aplicada'), findsNothing);
    await accept(tester);
    expect(find.text(r'Cobrar: $40.00'), findsOneWidget);
  });

  check('fallo antes de aplicar permite reintento con mismo operationId', (
    tester,
  ) async {
    await open(tester);
    commands.beforeApply = () async => throw StateError('Fallo local');
    await tester.tap(toggle);
    await settle(tester);
    expect(find.text('Precio de oferta · Normal'), findsOneWidget);
    commands.beforeApply = null;
    await tester.tap(toggle);
    await settle(tester);
    expect(commands.attempts, hasLength(2));
    expect(commands.attempts[0].operationId, commands.attempts[1].operationId);
    expect(find.text('Precio de oferta · Activo'), findsOneWidget);
  });

  check('respuesta perdida recupera éxito persistido sin repetir cambio', (
    tester,
  ) async {
    await open(tester);
    commands.failAfterApply = true;
    await tester.tap(toggle);
    await settle(tester);
    expect(find.text('Precio de oferta · Activo'), findsOneWidget);
    expect(commands.attempts, hasLength(1));
    expect(
      (await tester.runAsync(
        () => h.db.select(h.db.sales).get(),
      ))!.single.pricingMode,
      'offer',
    );
  });

  check('servidor incompatible explica acción y no cambia venta', (
    tester,
  ) async {
    await open(tester);
    capabilities.capabilities = null;
    await tester.tap(toggle);
    await settle(tester);
    expect(
      find.textContaining(
        'servidor esté actualizado para usar precios de oferta',
      ),
      findsOneWidget,
    );
    expect(find.text('Precio de oferta · Normal'), findsOneWidget);
    expect(await tester.runAsync(() => h.db.select(h.db.sales).get()), isEmpty);
  });

  check('legado conserva captura y bloquea tarifa con instrucción accionable', (
    tester,
  ) async {
    await open(tester);
    await add(tester);
    await tester.runAsync(
      () => h.db
          .update(h.db.saleItems)
          .write(
            const SaleItemsCompanion(
              priceSnapshotVersion: Value(null),
              normalPriceMinorSnapshot: Value(null),
              offerPriceMinorSnapshot: Value(null),
              effectivePriceSource: Value(null),
              priceSelection: Value(null),
              priceConfigurationEventId: Value(null),
            ),
          ),
    );
    await settle(tester);
    expect(
      find.text('Precio capturado · tarifa sin acreditar'),
      findsOneWidget,
    );
    await tester.tap(toggle);
    await settle(tester);
    await capture(tester, 'error-legado-420x950');
    expect(find.textContaining('Recaptura las líneas legadas'), findsOneWidget);
    expect(find.text(r'Cobrar: $35.00'), findsOneWidget);
    expect(commands.attempts, isEmpty);
  });

  check('reinicio SQLite en disco recupera oferta y snapshots en Caja', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('offer-ui-restart-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    await tester.runAsync(h.dispose);
    final path = '${dir.path}/test.sqlite';
    h = QuotationHarness(
      database: AppDatabase.forTesting(NativeDatabase(File(path))),
      mode: AppMode.serverSync,
    );
    connect();
    await open(tester);
    await add(tester);
    await accept(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await tester.runAsync(h.dispose);
    h = QuotationHarness(
      database: AppDatabase.forTesting(NativeDatabase(File(path))),
      mode: AppMode.serverSync,
    );
    connect();
    await open(tester, seed: false);
    expect(find.text('Precio de oferta · Activo'), findsOneWidget);
    expect(find.text('Oferta aplicada'), findsOneWidget);
    expect(find.text(r'Cobrar: $20.00'), findsOneWidget);
  });

  check('lector HID simulado usa oferta y recupera foco tras alternar', (
    tester,
  ) async {
    await open(tester, physical: true);
    await tester.runAsync(
      () => h.db.productoDao.actualizarVariante(
        QuotationHarness.directId,
        const ProductVariantsCompanion(barcode: Value('001')),
      ),
    );
    await tester.tap(toggle);
    await settle(tester);
    final field = find.byKey(const Key('physical_barcode_input'));
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    tester.widget<TextField>(field).controller!.text = '001';
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(find.text(r'Cobrar: $20.00'), findsOneWidget);
    expect(find.text('Oferta aplicada'), findsOneWidget);
    await accept(tester);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(find.text(r'Cobrar: $35.00'), findsOneWidget);
  });

  check('cámara simulada desde Caja agrega con tarifa activa', (tester) async {
    final original = MobileScannerPlatform.instance;
    final camera = FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = camera;
    MobileScannerController.resetPlatformSessionOwner();
    addTearDown(() async {
      MobileScannerPlatform.instance = original;
      MobileScannerController.resetPlatformSessionOwner();
      await camera.captures.close();
    });
    await open(tester);
    await tester.runAsync(
      () => h.db.productoDao.actualizarVariante(
        QuotationHarness.directId,
        const ProductVariantsCompanion(barcode: Value('001')),
      ),
    );
    await tester.tap(toggle);
    await settle(tester);
    await tester.tap(find.byTooltip('Escanear código de barras'));
    await settle(tester);
    camera.captures.add(BarcodeCapture(barcodes: [Barcode(rawValue: '001')]));
    await settle(tester);
    expect(find.text(r'Precio: $20.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sale_barcode_go_to_caja')));
    await settle(tester);
    expect(find.text('Oferta aplicada'), findsOneWidget);
    expect(find.text(r'Cobrar: $20.00'), findsOneWidget);
  });

  for (final byAmount in [false, true]) {
    check(
      'búsqueda medida ${byAmount ? 'por importe' : 'por peso'}, edición y cantidad conservada al alternar',
      (tester) async {
        await open(tester);
        await tester.runAsync(
          () => h.db.productoDao.actualizarVariante(
            QuotationHarness.measuredId,
            const ProductVariantsCompanion(
              salePriceMinor: Value(5000),
              offerPriceMinor: Value(4000),
            ),
          ),
        );
        await tester.tap(toggle);
        await settle(tester);
        await tester.tap(find.byType(TextField).first);
        await settle(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp(r'^Café medido, Original,')),
        );
        await settle(tester);
        expect(find.text(r'Precio: $40.00 / 1 kg'), findsOneWidget);
        await tester.enterText(
          find.byKey(
            ValueKey(
              byAmount ? 'sale-target-amount' : 'sale-measured-quantity',
            ),
          ),
          byAmount ? '10' : '0.700',
        );
        await settle(tester);
        await tester.tap(find.text('Agregar'));
        await settle(tester);
        await tester.tap(find.text('Ir a caja (1 artículo)'));
        await settle(tester);
        expect(
          find.text(byAmount ? r'Cobrar: $10.00' : r'Cobrar: $28.00'),
          findsOneWidget,
        );
        await accept(tester);
        expect(
          find.text(byAmount ? r'Cobrar: $12.50' : r'Cobrar: $35.00'),
          findsOneWidget,
        );
        final sale = (await tester.runAsync(
          () => drafts.watchCurrentDraft().first,
        ))!;
        expect(sale.items.single.measuredQuantityAtomic, byAmount ? 250 : 700);
        await tester.tap(find.byTooltip('Editar artículo'));
        await settle(tester);
        await tester.enterText(
          find.byKey(const Key('draft_item_quantity_field')),
          '1.250',
        );
        await settle(tester);
        expect(find.text(r'Cobrar: $62.50'), findsOneWidget);
      },
    );
  }

  check('piezas edición manual conserva precio efectivo', (tester) async {
    await open(tester);
    await add(tester);
    await accept(tester);
    await tester.tap(find.byTooltip('Editar artículo'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const Key('draft_item_quantity_field')),
      '3',
    );
    await settle(tester);
    expect(find.text(r'Cobrar: $60.00'), findsOneWidget);
    expect(find.text('Oferta aplicada'), findsOneWidget);
  });

  check('cobro obsoleto vuelve a Caja con tarifa, líneas y total actuales', (
    tester,
  ) async {
    await open(tester);
    await add(tester);
    getIt.registerSingleton<VentaCommandService>(
      VentaCommandService(
        drafts: h.db.saleDao,
        products: h.products,
        inventory: DriftInventoryProjectionStore(
          inventoryDao: h.db.inventoryDao,
          unitDao: h.db.unitDao,
        ),
        events: h.events,
        context: h.context,
      ),
    );
    await tester.tap(find.text(r'Cobrar: $35.00'));
    await settle(tester);
    final sale = (await tester.runAsync(
      () => drafts.watchCurrentDraft().first,
    ))!;
    await tester.runAsync(
      () => commands.cambiarTarifa(
        CambiarTarifaVentaBorradorCommand(
          operationId: '00000000-0000-4000-8000-000000000099',
          saleId: sale.id,
          pricingMode: 'offer',
          expectedVersion: sale.version,
          expectedDraftEventId: sale.lastEventId,
          expectedTotalMinor: sale.totalMinor,
        ),
      ),
    );
    await tester.tap(find.text('Recibido por efectivo'));
    await settle(tester);
    expect(find.byType(PaymentMethodScreen), findsNothing);
    expect(find.text('Precio de oferta · Activo'), findsOneWidget);
    expect(find.text(r'Cobrar: $20.00'), findsOneWidget);
    expect(find.textContaining('Revísalo antes de cobrar.'), findsOneWidget);
    await capture(tester, 'error-cobro-420x950');
    expect(
      (await tester.runAsync(
        () => h.db.select(h.db.sales).get(),
      ))!.single.status,
      'borrador',
    );
  });

  check('texto ampliado mantiene revisión y controles accesibles', (
    tester,
  ) async {
    await open(tester, size: const Size(360, 740), textScale: 1.6);
    await add(tester);
    await add(tester, QuotationHarness.recipeId);
    await capture(tester, 'caja-texto-160-360x740');
    await tester.tap(toggle);
    await settle(tester);
    await capture(tester, 'revision-texto-160-360x740');
    await tester.tap(confirm);
    await settle(tester);
    expect(find.text(r'Cobrar: $44.00'), findsOneWidget);
  });

  for (final size in [
    const Size(360, 740),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    check(
      'visual y flujo captura búsqueda, cobro y ticket ${size.width.toInt()}',
      (tester) async {
        final label = '${size.width.toInt()}x${size.height.toInt()}';
        await open(tester, size: size);
        final semantics = tester.ensureSemantics();

        await add(tester);
        await add(tester, QuotationHarness.recipeId);
        await capture(tester, 'caja-normal-$label');
        await tester.tap(toggle);
        await settle(tester);
        await capture(tester, 'revision-$label');
        await tester.tap(confirm);
        await settle(tester);
        expect(
          tester
              .getSemantics(find.byKey(const Key('sale_pricing_state')))
              .getSemanticsData()
              .flagsCollection
              .isToggled,
          ui.Tristate.isTrue,
        );
        semantics.dispose();
        await capture(tester, 'caja-oferta-$label');
        // Búsqueda real, con condiciones capturadas y agregado repetido.
        await tester.tap(find.byType(TextField).first);
        await settle(tester);
        await tester.tap(
          find.bySemanticsLabel(RegExp(r'^Pan, Original, \$35.00')),
        );
        await settle(tester);
        await tester.tap(find.text('Ir a caja (2 artículos)'));
        await settle(tester);
        expect(find.text(r'Cobrar: $64.00'), findsOneWidget);
        getIt.registerSingleton<VentaCommandService>(
          VentaCommandService(
            drafts: h.db.saleDao,
            products: h.products,
            inventory: DriftInventoryProjectionStore(
              inventoryDao: h.db.inventoryDao,
              unitDao: h.db.unitDao,
            ),
            events: h.events,
            context: h.context,
          ),
        );
        final confirmed = ConfirmedSaleRepositoryImpl(
          DriftConfirmedSaleStore(h.db),
        );
        getIt.registerSingleton<ConfirmedSaleRepository>(confirmed);
        await tester.tap(find.text(r'Cobrar: $64.00'));
        await settle(tester);
        expect(
          tester
              .widget<PaymentMethodScreen>(find.byType(PaymentMethodScreen))
              .expectedVersion,
          4,
        );
        await capture(tester, 'cobro-$label');
        await tester.tap(find.byKey(const Key('payment_tab_transfer')));
        await settle(tester);
        await tester.tap(find.text('Confirmar transferencia'));
        await settle(tester);
        await pumpReceiptImage(tester);
        expect(find.byType(SaleReceiptScreen), findsOneWidget);
        final sale = (await tester.runAsync(
          () => confirmed.watchSales().first,
        ))!.single;
        expect(sale.totalMinor, 6400);
        expect(sale.items.map((l) => l.unitPriceMinor), contains(2000));
        await capture(tester, 'ticket-$label');
        await tester.drag(find.byType(Image), const Offset(0, -600));
        await settle(tester);
        await capture(tester, 'ticket-total-$label');
      },
    );
  }
}
