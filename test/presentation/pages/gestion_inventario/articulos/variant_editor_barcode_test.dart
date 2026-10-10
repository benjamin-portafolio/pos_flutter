import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pos_flutter/domain/inventario/dimension_unidad.dart';
import 'package:pos_flutter/domain/inventario/unidad_inventario.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/models/articulo_form_result.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/articulos/widgets/variant_editor_screen.dart';

import '../../../../support/fake_mobile_scanner_platform.dart';

/// Anatomía y contrato del campo de código de barras del editor de variante.
void main() {
  late MobileScannerPlatform originalPlatform;
  late FakeMobileScannerPlatform camera;

  setUp(() {
    originalPlatform = MobileScannerPlatform.instance;
    camera = FakeMobileScannerPlatform();
    MobileScannerPlatform.instance = camera;
    MobileScannerController.resetPlatformSessionOwner();
  });

  tearDown(() async {
    await camera.captures.close();
    MobileScannerPlatform.instance = originalPlatform;
    MobileScannerController.resetPlatformSessionOwner();
  });

  testWidgets('el campo muestra la etiqueta, la ayuda y la pista del video', (
    tester,
  ) async {
    await _pumpEditor(tester);

    expect(find.text('¿Código de barras?'), findsOneWidget);
    expect(find.byKey(const Key('variant_barcode_help_icon')), findsOneWidget);
    expect(find.text('Ej. 750802876102'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('variant_barcode_card')),
        matching: find.byKey(const Key('variant_barcode_field')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('solo admite dígitos: el teclado numérico descarta letras', (
    tester,
  ) async {
    await _pumpEditor(tester);
    final field = find.byKey(const Key('variant_barcode_field'));

    await tester.enterText(field, '7508AB0210-34');
    await tester.pump();

    expect(_field(tester).controller!.text, '7508021034');
    expect(_input(tester).keyboardType, TextInputType.number);
  });

  testWidgets('no se implementó GENERAR: no existe ese botón', (tester) async {
    await _pumpEditor(tester);

    expect(find.text('GENERAR'), findsNothing);
  });

  testWidgets('ESCANEAR navega a la pantalla de escaneo', (tester) async {
    await _pumpEditor(tester);

    await tester.tap(find.byKey(const Key('scan_barcode_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barcode_scanner_screen')), findsOneWidget);
    expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
    expect(camera.lastStartOptions?.cameraDirection, CameraFacing.back);
    expect(
      find.text(
        'Escanee el código de barras aquí para actualizar artículos o '
        'crear nuevos.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
    await tester.pumpAndSettle();
  });

  testWidgets('el X cierra la pantalla, devuelve null y no toca el campo', (
    tester,
  ) async {
    VariantEditorResult? result;
    await _pumpEditor(
      tester,
      initial: const ArticuloFormVarianteResult(
        nombre: 'Grande',
        precioVenta: '10.00',
        costoEstandar: null,
        codigoBarras: '750802876102',
      ),
      onSaved: (value) => result = value,
    );

    await tester.tap(find.byKey(const Key('scan_barcode_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('barcode_scanner_screen')), findsNothing);
    expect(_field(tester).controller!.text, '750802876102');
    expect(camera.stops, 1);
    expect(camera.disposals, 1);

    // Cancelar devuelve null: lo que se guarda sigue siendo el valor previo.
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    expect(result?.value?.codigoBarras, '750802876102');
  });

  testWidgets('el valor devuelto por la pantalla se setea y lo guarda _save', (
    tester,
  ) async {
    VariantEditorResult? result;
    await _pumpEditor(tester, onSaved: (value) => result = value);
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );

    await tester.tap(find.byKey(const Key('scan_barcode_button')));
    await tester.pumpAndSettle();
    camera.captures.add(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '012345678905')]),
    );
    await tester.pumpAndSettle();

    expect(_field(tester).controller!.text, '012345678905');
    expect(camera.stops, 1);
    expect(camera.disposals, 1);

    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    expect(result?.value?.codigoBarras, '012345678905');
  });

  testWidgets('CodigoBarras rechaza un valor devuelto que no es dígito', (
    tester,
  ) async {
    VariantEditorResult? result;
    await _pumpEditor(tester, onSaved: (value) => result = value);

    await tester.tap(find.byKey(const Key('scan_barcode_button')));
    await tester.pumpAndSettle();
    camera.captures.add(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '7508-0287')]),
    );
    await tester.pumpAndSettle();

    // El mensaje del value object aparece en el formulario, no se traga.
    expect(find.byKey(const Key('variant_barcode_error')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('variant_barcode_error'))).data,
      'Solo admite dígitos, hasta 32 caracteres.',
    );
    expect(_field(tester).controller!.text, isEmpty);

    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    expect(result?.value?.codigoBarras, isNull);
  });

  testWidgets('ignora lecturas vacías y acepta solo la primera lectura', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await tester.tap(find.byKey(const Key('scan_barcode_button')));
    await tester.pumpAndSettle();

    camera.captures.add(const BarcodeCapture());
    camera.captures.add(
      const BarcodeCapture(
        barcodes: [
          Barcode(),
          Barcode(rawValue: '  '),
        ],
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('barcode_scanner_screen')), findsOneWidget);

    final detect = tester
        .widget<MobileScanner>(find.byType(MobileScanner))
        .onDetect!;
    detect(const BarcodeCapture(barcodes: [Barcode(rawValue: '012345678905')]));
    detect(const BarcodeCapture(barcodes: [Barcode(rawValue: '99999999')]));
    await tester.pumpAndSettle();

    expect(find.byType(VariantEditorScreen), findsOneWidget);
    expect(_field(tester).controller!.text, '012345678905');
  });

  testWidgets('volver conserva el campo e ignora lecturas durante la salida', (
    tester,
  ) async {
    await _pumpEditor(
      tester,
      initial: const ArticuloFormVarianteResult(
        nombre: 'Grande',
        precioVenta: '10.00',
        costoEstandar: null,
        codigoBarras: '750802876102',
      ),
    );
    await tester.tap(find.byKey(const Key('scan_barcode_button')));
    await tester.pumpAndSettle();
    final detect = tester
        .widget<MobileScanner>(find.byType(MobileScanner))
        .onDetect!;

    await tester.binding.handlePopRoute();
    detect(const BarcodeCapture(barcodes: [Barcode(rawValue: '99999999')]));
    await tester.pumpAndSettle();

    expect(find.byType(VariantEditorScreen), findsOneWidget);
    expect(_field(tester).controller!.text, '750802876102');
    expect(camera.stops, 1);
    expect(camera.disposals, 1);
  });

  testWidgets('pausa la cámara en segundo plano y reanuda la lectura', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await tester.tap(find.byKey(const Key('scan_barcode_button')));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    camera.captures.add(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '99999999')]),
    );
    await tester.pump();
    expect(camera.stops, 1);
    expect(find.byKey(const Key('barcode_scanner_screen')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(camera.starts, 2);

    camera.captures.add(
      const BarcodeCapture(barcodes: [Barcode(rawValue: '012345678905')]),
    );
    await tester.pumpAndSettle();
    expect(_field(tester).controller!.text, '012345678905');
  });

  for (final errorCode in [
    MobileScannerErrorCode.permissionDenied,
    MobileScannerErrorCode.unsupported,
    MobileScannerErrorCode.genericError,
  ]) {
    testWidgets('muestra un mensaje y permite cancelar con $errorCode', (
      tester,
    ) async {
      camera.startError = MobileScannerException(errorCode: errorCode);
      await _pumpEditor(tester);
      await tester.tap(find.byKey(const Key('scan_barcode_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('barcode_scanner_error')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('barcode_scanner_error')))
            .data,
        contains(switch (errorCode) {
          MobileScannerErrorCode.permissionDenied => 'ajustes del dispositivo',
          MobileScannerErrorCode.unsupported => 'No hay una cámara disponible',
          _ => 'No se pudo iniciar la cámara',
        }),
      );
      await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
      await tester.pumpAndSettle();
      expect(_field(tester).controller!.text, isEmpty);
    });
  }

  testWidgets(
    'un fallo del plugin muestra el error sin dejar la carga activa',
    (tester) async {
      camera.startError = MissingPluginException('Cámara no disponible');
      await _pumpEditor(tester);
      await tester.tap(find.byKey(const Key('scan_barcode_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('barcode_scanner_error')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
      await tester.pumpAndSettle();
      expect(_field(tester).controller!.text, isEmpty);
    },
  );

  testWidgets('libera la cámara si se cierra mientras solicita permiso', (
    tester,
  ) async {
    camera.startGate = Completer<void>();
    await _pumpEditor(tester);
    await tester.tap(find.byKey(const Key('scan_barcode_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(camera.starts, 1);

    await tester.tap(find.byKey(const Key('close_barcode_scanner_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('barcode_scanner_screen')), findsNothing);

    camera.startGate!.complete();
    await tester.pumpAndSettle();
    expect(camera.stops, 1);
    expect(camera.disposals, 1);
    expect(_field(tester).controller!.text, isEmpty);
  });

  testWidgets('rechaza 33 dígitos con el mensaje del value object', (
    tester,
  ) async {
    VariantEditorResult? result;
    await _pumpEditor(tester, onSaved: (value) => result = value);
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('variant_barcode_field')),
      '1' * 33,
    );

    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('Solo admite dígitos, hasta 32 caracteres.'),
      findsOneWidget,
    );
    expect(result, isNull, reason: 'no debe guardar con un código inválido');
  });

  testWidgets('guarda el valor normalizado por el value object', (
    tester,
  ) async {
    VariantEditorResult? result;
    await _pumpEditor(tester, onSaved: (value) => result = value);
    await tester.enterText(
      find.byKey(const Key('variant_sale_price_field')),
      '10',
    );
    // Entrada cruda: el value object recorta antes de guardar.
    await tester.enterText(
      find.byKey(const Key('variant_barcode_field')),
      '012345678905',
    );

    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    expect(result?.value?.codigoBarras, '012345678905');
  });

  testWidgets('un código vacío se guarda como null, no como cadena', (
    tester,
  ) async {
    VariantEditorResult? result;
    await _pumpEditor(
      tester,
      initial: const ArticuloFormVarianteResult(
        nombre: 'Grande',
        precioVenta: '10.00',
        costoEstandar: null,
        codigoBarras: '750802876102',
      ),
      onSaved: (value) => result = value,
    );
    await tester.enterText(find.byKey(const Key('variant_barcode_field')), '');

    await tester.tap(find.byKey(const Key('save_variant_button')));
    await tester.pumpAndSettle();

    expect(result?.value?.codigoBarras, isNull);
  });

  testWidgets('el campo precarga el código existente y respeta preview', (
    tester,
  ) async {
    const initial = ArticuloFormVarianteResult(
      nombre: 'Grande',
      precioVenta: '10.00',
      costoEstandar: null,
      codigoBarras: '750802876102',
    );
    await _pumpEditor(tester, initial: initial);
    expect(_field(tester).controller!.text, '750802876102');

    await _pumpEditor(tester, initial: initial, preview: true);
    expect(_input(tester).readOnly, isTrue);
  });

  testWidgets('la fila campo y botón no desborda en pantallas angostas', (
    tester,
  ) async {
    for (final width in [280.0, 320.0, 360.0, 480.0, 720.0]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await _pumpEditor(tester);
      await tester.enterText(
        find.byKey(const Key('variant_barcode_field')),
        '750802876102',
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'sin desbordes a $width px',
      );
    }
  });
}

TextFormField _field(WidgetTester tester) =>
    tester.widget(find.byKey(const Key('variant_barcode_field')));

/// `TextFormField` no expone teclado ni solo-lectura: viven en el `EditableText`
/// que construye por dentro.
EditableText _input(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(
    of: find.byKey(const Key('variant_barcode_field')),
    matching: find.byType(EditableText),
  ),
);

const _piece = UnidadInventario(
  id: 'pza',
  code: 'pza',
  nombre: 'Pieza',
  simbolo: 'pza',
  dimension: DimensionUnidad.count,
  factorAtomico: 1,
  maximosDecimales: 0,
  activa: true,
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  ArticuloFormVarianteResult? initial,
  bool preview = false,
  ValueChanged<VariantEditorResult?>? onSaved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // Clave nueva en cada llamada: si se reusa el árbol, el `Navigator`
      // conserva la ruta del editor de la iteración anterior y el botón
      // `open_editor` queda fuera de pantalla.
      key: UniqueKey(),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            key: const Key('open_editor'),
            onPressed: () async {
              // El `await` va fuera del `?.` a propósito: si se encadenara,
              // `push` no se ejecutaría cuando no hay `onSaved` y el editor
              // nunca se abriría.
              final saved = await Navigator.of(context)
                  .push<VariantEditorResult>(
                    MaterialPageRoute(
                      builder: (_) => VariantEditorScreen(
                        initialValue: initial,
                        preview: preview,
                        canDelete: false,
                        existingNameKeys: const {},
                        inventoryUnit: _piece,
                      ),
                    ),
                  );
              onSaved?.call(saved);
            },
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open_editor')));
  await tester.pumpAndSettle();
}
