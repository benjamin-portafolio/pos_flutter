import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/domain/articulos/proveedor_variante.dart';
import 'package:pos_flutter/domain/articulos/sale_configuration.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/domain/proveedores/proveedor.dart';
import 'package:pos_flutter/domain/repositories/proveedor_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_result.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/proveedor_precio_form.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/proveedor_precios_form_result.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_suppliers_editor_screen.dart';

const a = '00000000-0000-4000-8000-000000000002';
const b = '00000000-0000-4000-8000-000000000003';
const at = 1791331200123;
const piece = UnidadInventario(
  id: 'pza',
  code: 'pza',
  nombre: 'Pieza',
  simbolo: 'pza',
  dimension: DimensionUnidad.count,
  factorAtomico: 1,
  maximosDecimales: 0,
  activa: true,
);
const kg = UnidadInventario(
  id: 'kg',
  code: 'kg',
  nombre: 'Kilogramo',
  simbolo: 'kg',
  dimension: DimensionUnidad.mass,
  factorAtomico: 1000,
  maximosDecimales: 3,
  activa: true,
);
const catalog = [
  Proveedor(
    id: a,
    nombre: 'Distribuidora Norte',
    version: 1,
    createdEventId: null,
    lastEventId: null,
    lastServerSequence: null,
  ),
  Proveedor(
    id: b,
    nombre: 'Proveedor Sur',
    version: 1,
    createdEventId: null,
    lastEventId: null,
    lastServerSequence: null,
  ),
];
ProveedorVariante quote([String id = a, int price = 1234]) => ProveedorVariante(
  proveedorId: id,
  precioInformadoMenor: price,
  fechaInformadaMs: at,
);

class _Catalog implements ProveedorRepository {
  _Catalog(this.stream) : data = null;
  _Catalog.data(this.data) : stream = null;
  final Stream<List<Proveedor>>? stream;
  final List<Proveedor>? data;
  @override
  Stream<List<Proveedor>> watchProveedores() =>
      data == null ? stream! : Stream.value(data!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previewFonts = Platform.environment['POS_SUPPLIER_PREVIEW_FONTS'];
  setUpAll(() async {
    if (previewFonts == null) return;
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(
          '$previewFonts/${entry.value}',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });
  late AppConfigController config;
  setUp(() => config = AppConfigController(AppConfig.initial));
  tearDown(() => config.dispose());

  Future<void> click(WidgetTester tester, String key) async {
    await tester.pump();
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    ValueChanged<ProveedorPreciosFormResult?>? onResult,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                final result = await Navigator.of(context)
                    .push<ProveedorPreciosFormResult>(
                      MaterialPageRoute(builder: (_) => screen),
                    );
                onResult?.call(result);
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  Widget editor({
    List<ProveedorVariante> initial = const [],
    ProveedorRepository? repository,
  }) => VariantSuppliersEditorScreen(
    repository: repository ?? _Catalog.data(catalog),
    config: config,
    initialValue: initial,
    presentationLabel: 'Café · Bolsa 500 g',
    priceBasis: 'Precio por una unidad vendible de esta presentación.',
  );

  testWidgets(
    'selección explícita, varios proveedores, cero/coma/punto y sin duplicados',
    (tester) async {
      ProveedorPreciosFormResult? result;
      await open(tester, editor(), onResult: (v) => result = v);
      expect(
        find.byKey(const Key('supplier_presentation_label')),
        findsOneWidget,
      );
      expect(find.textContaining('pestaña PROVEEDORES'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      for (final id in [a, b]) {
        await click(tester, 'select_variant_supplier_$id');
      }
      await tester.enterText(
        find.byKey(const Key('supplier_price_$a')),
        '0,00',
      );
      await tester.enterText(
        find.byKey(const Key('supplier_price_$b')),
        '12.34',
      );
      await click(tester, 'save_variant_suppliers_button');
      expect(result!.proveedores.map((r) => r.proveedorId), [a, b]);
      expect(result!.proveedores.map((r) => r.precioInformadoMenor), [0, 1234]);
      expect(() => result!.proveedores.clear(), throwsUnsupportedError);
    },
  );

  for (final invalid in ['', '-1', '1.234', 'abc', '90071992547409.92']) {
    testWidgets(
      'error por campo "$invalid" conserva selección y permite corregir',
      (tester) async {
        ProveedorPreciosFormResult? result;
        await open(
          tester,
          editor(initial: [quote()]),
          onResult: (v) => result = v,
        );
        await tester.enterText(
          find.byKey(const Key('supplier_price_$a')),
          invalid,
        );
        await click(tester, 'save_variant_suppliers_button');
        expect(result, isNull);
        expect(
          find.byKey(const Key('variant_suppliers_save_error')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const Key('select_variant_supplier_$a')),
              )
              .value,
          isTrue,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('supplier_price_$a')))
              .controller!
              .text,
          invalid,
        );
        await tester.enterText(find.byKey(const Key('supplier_price_$a')), '0');
        await click(tester, 'save_variant_suppliers_button');
        expect(result!.proveedores.single.precioInformadoMenor, 0);
      },
    );
  }
  testWidgets('carga exacta y precio equivalente conservan fecha al reabrir', (
    tester,
  ) async {
    ProveedorPreciosFormResult? result;
    await open(tester, editor(initial: [quote()]), onResult: (v) => result = v);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('supplier_price_$a')))
          .controller!
          .text,
      '12.34',
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('supplier_date_$a')))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const Key('supplier_price_$a')), '12,34');
    await click(tester, 'save_variant_suppliers_button');
    expect(result!.proveedores.single, quote());
    await open(tester, editor(initial: result!.proveedores));
    expect(
      find.textContaining(ProveedorPrecioForm.formatDate(at)),
      findsOneWidget,
    );
  });
  testWidgets(
    'cambiar precio habilita fecha informada; cancelar/calendario respeta el borrador',
    (tester) async {
      ProveedorPreciosFormResult? result;
      await open(
        tester,
        editor(initial: [quote()]),
        onResult: (v) => result = v,
      );
      await tester.enterText(find.byKey(const Key('supplier_price_$a')), '15');
      await click(tester, 'supplier_date_$a');
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await click(tester, 'supplier_date_$a');
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await click(tester, 'select_variant_supplier_$a');
      await click(tester, 'select_variant_supplier_$a');
      await click(tester, 'save_variant_suppliers_button');
      final day = ProveedorPrecioForm.dateFromMilliseconds(at)!;
      expect(
        result!.proveedores.single.fechaInformadaMs,
        DateTime(day.year, day.month, 20).toUtc().millisecondsSinceEpoch,
      );
      expect(result!.proveedores.single.precioInformadoMenor, 1500);
    },
  );
  testWidgets('retirar último, re-seleccionar y retirar produce lista vacía', (
    tester,
  ) async {
    ProveedorPreciosFormResult? result;
    await open(tester, editor(initial: [quote()]), onResult: (v) => result = v);
    for (var i = 0; i < 3; i++) {
      await click(tester, 'select_variant_supplier_$a');
    }
    expect(find.byKey(const Key('supplier_price_$a')), findsNothing);
    await click(tester, 'save_variant_suppliers_button');
    expect(result!.proveedores, isEmpty);
  });
  testWidgets('cancelar selector devuelve null', (tester) async {
    var returned = false;
    ProveedorPreciosFormResult? result;
    await open(
      tester,
      editor(initial: [quote()]),
      onResult: (v) {
        returned = true;
        result = v;
      },
    );
    await tester.enterText(find.byKey(const Key('supplier_price_$a')), '35');
    await click(tester, 'close_variant_suppliers_button');
    expect(returned, isTrue);
    expect(result, isNull);
  });
  testWidgets(
    'carga, error, reintento y catálogo vacío permiten guardar vacío',
    (tester) async {
      final updates = StreamController<List<Proveedor>>.broadcast();
      await tester.pumpWidget(
        MaterialApp(home: editor(repository: _Catalog(updates.stream))),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('variant_suppliers_loading')),
        findsOneWidget,
      );
      updates.addError(StateError('fallo de lectura'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('variant_suppliers_error')), findsOneWidget);
      await click(tester, 'retry_variant_suppliers_button');
      updates.add([]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('variant_suppliers_empty')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('save_variant_suppliers_button')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await updates.close();
      ProveedorPreciosFormResult? result;
      await open(
        tester,
        editor(repository: _Catalog.data([])),
        onResult: (v) => result = v,
      );
      await click(tester, 'save_variant_suppliers_button');
      expect(result!.proveedores, isEmpty);
    },
  );
  testWidgets(
    'recargas no pierden campos ni convierten catálogo faltante en retirada',
    (tester) async {
      final updates = StreamController<List<Proveedor>>.broadcast();
      await tester.pumpWidget(
        MaterialApp(
          home: editor(
            initial: [quote()],
            repository: _Catalog(updates.stream),
          ),
        ),
      );
      updates.add(catalog);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('supplier_price_$a')), '37');
      updates.add([]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('supplier_price_$a')))
            .controller!
            .text,
        '37',
      );
      await click(tester, 'save_variant_suppliers_button');
      expect(find.textContaining('Proveedor no disponible.'), findsOneWidget);
      updates.add(catalog);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('supplier_price_$a')))
            .controller!
            .text,
        '37',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await updates.close();
    },
  );
  testWidgets('server_sync conserva selector y permite captura offline', (
    tester,
  ) async {
    await open(tester, editor());
    await click(tester, 'select_variant_supplier_$a');
    config.update(config.config.copyWith(mode: AppMode.serverSync));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('variant_suppliers_unavailable')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('save_variant_suppliers_button')),
      findsOneWidget,
    );
    await open(tester, editor());
    expect(
      find.byKey(const Key('variant_suppliers_unavailable')),
      findsNothing,
    );
  });

  Widget variant({bool preview = false, SaleConfiguration sale = const UnitSaleConfiguration()}) => VariantEditorScreen(
    initialValue: ArticuloFormVarianteResult.conProveedores(id: 'variant', nombre: 'Bolsa 500 g', precioVenta: '25', costoEstandar: '3', proveedores: [quote()]),
    preview: preview, canDelete: false, existingNameKeys: {}, inventoryUnit: piece,
    inventoryUnits: const [piece,kg], productName: 'Café', proveedorRepository: _Catalog.data(catalog), appConfigController: config, saleConfiguration: sale,
  );

  testWidgets(
    'consulta resume proveedores/precios/fechas sin acción de editar',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: variant(preview: true)));
      await tester.ensureVisible(
        find.byKey(const Key('variant_suppliers_summary')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Distribuidora Norte · \$12.34'),
        findsOneWidget,
      );
      expect(
        find.textContaining(ProveedorPrecioForm.formatDate(at)),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('manage_variant_suppliers_button')),
        findsNothing,
      );
      config.update(config.config.copyWith(mode: AppMode.serverSync));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('variant_suppliers_summary')),
        findsOneWidget,
      );
    },
  );
  testWidgets('base medida usa cantidad de referencia y presentación', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: variant(
          sale: MeasuredSaleConfiguration(
            saleUnitId: kg.id,
            priceReferenceQuantityAtomic: 500,
          ),
        ),
      ),
    );
    await click(tester, 'manage_variant_suppliers_button');
    expect(find.text('Precio por 0.5 kg.'), findsOneWidget);
    expect(find.text('Café · Bolsa 500 g'), findsOneWidget);
  });
  testWidgets(
    'editor de variante oculta proveedores sin configuración conocida',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VariantEditorScreen(
            initialValue: null,
            canDelete: false,
            existingNameKeys: {},
            inventoryUnit: piece,
          ),
        ),
      );
      expect(
        find.byKey(const Key('manage_variant_suppliers_button')),
        findsNothing,
      );
    },
  );
  testWidgets('variante abierta conserva borrador al cambiar a server_sync', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: variant()));
    await click(tester, 'manage_variant_suppliers_button');
    await tester.enterText(find.byKey(const Key('supplier_price_$a')), '30');
    await click(tester, 'save_variant_suppliers_button');
    config.update(config.config.copyWith(mode: AppMode.serverSync));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('manage_variant_suppliers_button')),
      findsOneWidget,
    );
    await click(tester, 'manage_variant_suppliers_button');
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('supplier_price_$a')))
          .controller!
          .text,
      '30.00',
    );
  });

  for (final scenario in [
    (const Size(320, 640), 1.3, 260.0),
    (const Size(740, 360), 1.3, 170.0),
    (const Size(1280, 800), 1.5, 300.0),
  ]) {
    testWidgets(
      'teléfono/tablet ${scenario.$1}, texto ${scenario.$2}, teclado y scroll',
      (tester) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final boundary = GlobalKey();
        final keyboard = ValueNotifier<double>(0);
        addTearDown(keyboard.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              fontFamily: previewFonts == null ? null : 'Roboto',
            ),
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: keyboard,
              builder: (context, inset, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scenario.$2),
                  viewInsets: EdgeInsets.only(bottom: inset),
                ),
                child: RepaintBoundary(key: boundary, child: child!),
              ),
            ),
            home: editor(initial: [quote(), quote(b, 0)]),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final output = Platform.environment['POS_SUPPLIER_PREVIEW_DIR'];
        Future<void> capture(String suffix) async {
          if (output == null) return;
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final screenshot = await render.toImage();
            final bytes = await screenshot.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/suppliers-${scenario.$1.width.toInt()}-$suffix.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            screenshot.dispose();
          });
        }

        await capture('initial');
        keyboard.value = scenario.$3;
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('supplier_price_$b')));
        await tester.enterText(
          find.byKey(const Key('supplier_price_$b')),
          '90071992547409.91',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture('keyboard');
        await tester.ensureVisible(
          find.byKey(const Key('save_variant_suppliers_button')),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .getRect(find.byKey(const Key('save_variant_suppliers_button')))
              .bottom,
          lessThanOrEqualTo(scenario.$1.height - scenario.$3),
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'consulta y editor de variante en ${scenario.$1}, texto ${scenario.$2}',
      (tester) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget page(bool preview) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scenario.$2)),
            child: child!,
          ),
          home: variant(preview: preview),
        );
        await tester.pumpWidget(page(true));
        await tester.ensureVisible(
          find.byKey(const Key('variant_suppliers_summary')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('manage_variant_suppliers_button')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(page(false));
        await click(tester, 'manage_variant_suppliers_button');
        expect(
          find.byKey(const Key('variant_suppliers_editor_screen')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
