import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/caja/models/sale_receipt_display.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_image_generator.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';
import 'package:share_plus/share_plus.dart';

import '../../../support/sale_draft_fixtures.dart';
import '../../../support/pump_receipt_image.dart';

ConfirmedSale _sale({List<SaleDraftItem>? items}) {
  final lines = items ?? sampleSale().items;
  final total = lines.fold(0, (sum, item) => sum + item.totalMinor);
  return ConfirmedSale(
    id: '12345678-1234-1234-1234-123456789012',
    createdAt: DateTime(2026, 9, 16, 20, 12),
    totalMinor: total,
    receivedMinor: total + 10000,
    changeMinor: 10000,
    currency: 'MXN',
    deliveryStatus: 'not_required',
    reason: null,
    items: lines,
  );
}

class _Repository implements ConfirmedSaleRepository {
  _Repository(this.stream);
  final Stream<List<ConfirmedSale>> stream;
  @override
  Stream<List<ConfirmedSale>> watchSales() => stream;
}

Finder _whatsAppButton() => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == 'WhatsApp',
);

Finder _shareButton() => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == 'Compartir',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cuenta variantes distintas y separa piezas, kilos y litros', () {
    final receipt = SaleReceiptDisplay(
      _sale(
        items: [
          ...sampleSale().items,
          measuredSaleItem,
          measuredSaleItem,
          const SaleDraftItem(
            id: 'liquid',
            variantId: 'liquid',
            productName: 'Leche',
            variantName: null,
            quantity: null,
            measuredQuantityAtomic: 250,
            unitPriceMinor: 1000,
            priceReferenceQuantityAtomic: 1000,
            unitCode: 'l',
            unitSymbol: 'L',
            unitAtomicFactor: 1000,
            totalMinor: 250,
          ),
        ],
      ),
    );
    expect(receipt.distinctItems, 5);
    expect(receipt.quantities, '5 pzas · 1.500 kg · 0.250 L');
    expect(receipt.itemRows[3], [
      'Café a granel\nTueste medio',
      r'$200.00 / 1 kg',
      '0.750 kg',
      r'$150.00',
    ]);
    expect(receipt.date, '16/09/2026 20:12');
    expect(receipt.totals, [
      ('Subtotal', r'$411.50'),
      ('Total general', r'$411.50'),
      ('Efectivo recibido', r'$511.50'),
      ('Cambio', r'$100.00'),
    ]);
    expect(receipt.semanticLabel, contains(receipt.sale.id));
    expect(receipt.semanticLabel, contains('MXN'));
    expect(receipt.semanticLabel, isNot(contains('MRP')));
  });

  test(
    'genera PNG completo y aumenta su altura con todas las líneas',
    () async {
      final generator = SaleReceiptImageGenerator();
      Future<ui.Image> render(List<SaleDraftItem> lines) async {
        final bytes = await generator.generate(
          SaleReceiptDisplay(_sale(items: lines)),
        );
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }

      final short = await render(sampleSale().items);
      final long = await render(List.filled(40, measuredSaleItem));
      try {
        expect(short.width, 880);
        expect(long.width, short.width);
        expect(long.height, greaterThan(short.height * 3));
        // El margen inferior forma parte del PNG y conserva fondo blanco opaco.
        final pixels = (await long.toByteData())!.buffer.asUint8List();
        expect(pixels.sublist(pixels.length - 4), [255, 255, 255, 255]);
      } finally {
        short.dispose();
        long.dispose();
      }
    },
  );

  testWidgets('muestra imagen, habilita compartir y permite una nueva venta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sale = _sale();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => SaleReceiptScreen(
                    saleId: sale.id,
                    repository: _Repository(Stream.value([sale])),
                  ),
                ),
              ),
              child: const Text('Abrir recibo'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir recibo'));
    await pumpReceiptImage(tester);
    final preview = tester.widget<Image>(find.byType(Image));
    expect(preview.image, isA<MemoryImage>());
    expect(preview.semanticLabel, contains(r'Cambio: $100.00'));
    for (final tooltip in ['SMS', 'Descargar', 'Imprimir', 'Más opciones']) {
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == tooltip,
              ),
            )
            .onPressed,
        isNull,
      );
    }
    expect(tester.widget<IconButton>(_whatsAppButton()).onPressed, isNotNull);
    expect(tester.widget<IconButton>(_shareButton()).onPressed, isNotNull);
    for (final label in ['Regresar', 'Borrar', 'Editar']) {
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
      );
    }
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Nueva venta'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir recibo'), findsOneWidget);
    expect(find.byType(SaleReceiptScreen), findsNothing);
  });

  testWidgets('maneja carga, venta ausente y errores del repositorio', (
    tester,
  ) async {
    final stream = StreamController<List<ConfirmedSale>>();
    addTearDown(stream.close);
    await tester.pumpWidget(
      MaterialApp(
        home: SaleReceiptScreen(
          saleId: 'absent',
          repository: _Repository(stream.stream),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<IconButton>(_whatsAppButton()).onPressed, isNull);
    stream.add([_sale()]);
    await tester.pumpAndSettle();
    expect(find.text('No se encontró la venta.'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.widget<IconButton>(_whatsAppButton()).onPressed, isNull);
    stream.addError(StateError('Lectura fallida'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo cargar el recibo de la venta.'),
      findsOneWidget,
    );
  });

  testWidgets('comparte el PNG completo una vez y permite cancelar y reabrir', (
    tester,
  ) async {
    final sale = _sale(items: List.filled(40, measuredSaleItem));
    final pending = Completer<ShareResult>();
    final requests = <ShareParams>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SaleReceiptScreen(
          saleId: sale.id,
          repository: _Repository(Stream.value([sale])),
          shareReceipt: (params) {
            requests.add(params);
            return pending.future;
          },
        ),
      ),
    );
    await pumpReceiptImage(tester);
    final preview =
        tester.widget<Image>(find.byType(Image)).image as MemoryImage;
    final button = _shareButton();
    final bounds = tester.getRect(button);
    await tester.tap(button);
    await tester.tap(_whatsAppButton());
    await tester.pump();
    expect(requests, hasLength(1));
    final params = requests.single;
    expect(params.files, hasLength(1));
    expect(params.files!.single.mimeType, 'image/png');
    expect(await params.files!.single.readAsBytes(), preview.bytes);
    expect(params.fileNameOverrides, ['ticket-${sale.id}.png']);
    expect(params.sharePositionOrigin, bounds);
    expect(params.downloadFallbackEnabled, isFalse);
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(tester.widget<IconButton>(_whatsAppButton()).onPressed, isNull);

    pending.complete(const ShareResult('', ShareResultStatus.dismissed));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(tester.widget<IconButton>(_whatsAppButton()).onPressed, isNotNull);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(_whatsAppButton());
    await tester.pumpAndSettle();
    expect(requests, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('permite reintentar al fallar y salir con el selector abierto', (
    tester,
  ) async {
    final sale = _sale();
    final pending = Completer<ShareResult>();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SaleReceiptScreen(
          saleId: sale.id,
          repository: _Repository(Stream.value([sale])),
          shareReceipt: (_) async {
            if (++attempts == 1) throw StateError('No disponible');
            return pending.future;
          },
        ),
      ),
    );
    await pumpReceiptImage(tester);
    await tester.tap(_whatsAppButton());
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo compartir el ticket. Inténtalo de nuevo.'),
      findsOneWidget,
    );
    expect(tester.widget<IconButton>(_whatsAppButton()).onPressed, isNotNull);
    await tester.tap(_whatsAppButton());
    await tester.pump();
    expect(attempts, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('Selector cerrado'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
