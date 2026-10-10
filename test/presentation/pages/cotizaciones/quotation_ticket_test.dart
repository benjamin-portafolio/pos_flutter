import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_item.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_estimate.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_line_estimate.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/domain/ventas/sale_draft_item.dart';
import 'package:pos_flutter/presentation/pages/caja/models/sale_receipt_display.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_image_generator.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/models/quotation_display.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotation_ticket_screen.dart';
import 'package:pos_flutter/presentation/tickets/ticket_image_generator.dart';
import 'package:share_plus/share_plus.dart';

import '../../../support/pump_receipt_image.dart';
import '../../../support/quotation_ui_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'P26: ticket separa creación/cálculo y conserva columnas monetarias y leyenda',
    () {
      final display = QuotationDisplay(
        sampleQuotation(),
        sampleEstimate(sampleQuotation()),
      );
      final ticket = display.ticket;
      expect(ticket.title, 'COTIZACIÓN');
      expect(ticket.identifier, 'Cotización # quotation-1');
      expect(ticket.date, '05/10/2026 09:30');
      expect(ticket.currency, 'MXN');
      expect(ticket.dateLabel, 'Fecha de creación');
      expect(ticket.details, contains('Precios vigentes al generar'));
      expect(ticket.details, contains(QuotationDisplay.recoveryNotice));
      expect(ticket.details, contains('Cálculo: ${display.calculatedAt}'));
      expect(
        display.estimate.calculatedAt,
        isNot(display.quotation.issuedAtLocal),
      );
      expect(ticket.footer, 'No representa un pago ni reserva existencias');
      expect(ticket.summary, isNull);
      expect(ticket.itemRows[1].skip(1), [
        r'$200.00 / 1 kg',
        '0.750 kg',
        r'$150.00',
      ]);
      expect(ticket.itemRows[2].skip(1), [
        r'$100.00 / 1 L',
        '0.250 L',
        r'$25.00',
      ]);
      expect(ticket.totals, [('Total estimado actual', r'$245.00')]);
      for (final excluded in [
        'Efectivo',
        'recibido',
        'Cambio',
        'deuda',
        '999',
        '998',
        'internal-key',
      ]) {
        expect(display.semanticLabel, isNot(contains(excluded)));
      }
    },
  );

  test(
    'PNG incluye todas las filas; exporta cotización y recibos para inspección',
    () async {
      if (Platform.environment['POS_QUOTATION_PNG_DIR'] != null) {
        final font = FontLoader('Roboto')
          ..addFont(
            File(
              '/System/Library/Fonts/Supplemental/Arial.ttf',
            ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await font.load();
      }
      final generator = TicketImageGenerator();
      final short = await generator.generate(
        QuotationDisplay(
          sampleQuotation(),
          sampleEstimate(sampleQuotation()),
        ).ticket,
      );
      final longQuotation = sampleQuotation(
        items: List.generate(18, (index) {
          final item = quotationLines[index % quotationLines.length];
          return QuotationItem(
            id: 'line-$index',
            sortOrder: index,
            variantId: item.variantId,
            productName: '${index + 1}. ${item.productName}',
            variantName: item.variantName,
            saleMode: item.saleMode,
            quantity: item.quantity,
            measuredQuantityAtomic: item.measuredQuantityAtomic,
            unitCode: item.unitCode,
            unitSymbol: item.unitSymbol,
            unitAtomicFactor: item.unitAtomicFactor,
          );
        }),
      );
      final long = await generator.generate(
        QuotationDisplay(longQuotation, sampleEstimate(longQuotation)).ticket,
      );
      Future<ui.Image> decode(Uint8List bytes) async {
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      }

      final shortImage = await decode(short);
      final longImage = await decode(long);
      try {
        expect(long.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect(shortImage.width, 880);
        expect(longImage.height, greaterThan(shortImage.height * 3));
        final pixels = (await longImage.toByteData())!.buffer.asUint8List();
        expect(pixels.sublist(pixels.length - 4), [255, 255, 255, 255]);
      } finally {
        shortImage.dispose();
        longImage.dispose();
      }
      final output = Platform.environment['POS_QUOTATION_PNG_DIR'];
      if (output != null) {
        await Directory(output).create(recursive: true);
        await File('$output/cotizacion-quotation-1.png').writeAsBytes(short);
        await File('$output/cotizacion-muchas-lineas.png').writeAsBytes(long);
        final q = sampleQuotation();
        final complete = sampleEstimate(q);
        final unavailable = QuotationEstimate(
          calculatedAt: complete.calculatedAt,
          totalMinor: null,
          lines: [
            complete.lines.first,
            const QuotationLineEstimate(
              quotationItemId: 'measured-line',
              issue: 'La variante ya no está disponible.',
            ),
            complete.lines.last,
          ],
        );
        await File('$output/cotizacion-no-disponible.png').writeAsBytes(
          await generator.generate(QuotationDisplay(q, unavailable).ticket),
        );
        for (final method in ['cash', 'transfer', 'credit']) {
          final sale = ConfirmedSale(
            id: 'receipt-$method',
            createdAt: longQuotation.issuedAtLocal,
            currency: 'MXN',
            totalMinor: sampleEstimate(longQuotation).totalMinor!,
            receivedMinor: method == 'cash'
                ? sampleEstimate(longQuotation).totalMinor! + 10000
                : 0,
            changeMinor: method == 'cash' ? 10000 : 0,
            paymentMethod: method,
            paymentReference: method == 'transfer' ? 'SPEI-2026' : null,
            clienteNombre: method == 'credit'
                ? 'Cliente con un nombre largo para verificar el recibo'
                : null,
            deliveryStatus: 'not_required',
            reason: null,
            items: [
              for (final item in longQuotation.items)
                SaleDraftItem(
                  id: item.id,
                  variantId: item.variantId,
                  productName: item.productName,
                  variantName: item.variantName,
                  quantity: item.quantity,
                  measuredQuantityAtomic: item.measuredQuantityAtomic,
                  unitPriceMinor: sampleEstimate(longQuotation).lines
                      .firstWhere((l) => l.quotationItemId == item.id)
                      .unitPriceMinor!,
                  priceReferenceQuantityAtomic: item.saleMode == 'unit'
                      ? null
                      : 1000,
                  unitCode: item.unitCode,
                  unitSymbol: item.unitSymbol,
                  unitAtomicFactor: item.unitAtomicFactor,
                  totalMinor: sampleEstimate(longQuotation).lines
                      .firstWhere((l) => l.quotationItemId == item.id)
                      .totalMinor!,
                ),
            ],
          );
          await File('$output/recibo-$method.png').writeAsBytes(
            await SaleReceiptImageGenerator().generate(
              SaleReceiptDisplay(sale),
            ),
          );
        }
      }
    },
  );

  testWidgets('carga por ID y muestra identidad, creación y precios vigentes', (
    tester,
  ) async {
    final repository = FakeQuotationRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: QuotationTicketScreen(
          quotationId: 'quotation-1',
          repository: repository,
        ),
      ),
    );
    await pumpReceiptImage(tester);
    expect(repository.reads, ['quotation-1']);
    final label = tester.widget<Image>(find.byType(Image)).semanticLabel!;
    expect(label, contains('05/10/2026 09:30'));
    expect(label, contains('COTIZACIÓN quotation-1'));
    expect(label, contains(r'$245.00 MXN'));
    expect(find.text('Nueva captura'), findsNothing);
    expect(find.text('Cerrar'), findsOneWidget);
    expect(tester.widget<IconButton>(_icon('Imprimir')).onPressed, isNotNull);
  });

  testWidgets(
    'compartir y WhatsApp serializan PNG completo; cancelar no limpia ni confirma entrega',
    (tester) async {
      final gate = Completer<ShareResult>();
      final requests = <ShareParams>[];
      final drafts = FakeQuotationDraftCommands();
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: 'quotation-1',
            repository: FakeQuotationRepository(),
            draftCommands: drafts,
            emissionDraft: const LimpiarVentaBorradorCommand(
              saleId: 'sale',
              expectedDraftEventId: 'draft-event',
            ),
            shareTicket: (request) {
              requests.add(request);
              return gate.future;
            },
          ),
        ),
      );
      await pumpReceiptImage(tester);
      final preview =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      final origin = tester.getRect(_icon('Compartir'));
      await tester.tap(_icon('Compartir'));
      await tester.tap(_icon('WhatsApp'));
      await tester.tap(find.text('Nueva captura'));
      await tester.pump();
      expect(requests, hasLength(1));
      expect(drafts.cleared, isEmpty);
      expect(requests.single.fileNameOverrides, ['cotizacion-quotation-1.png']);
      expect(requests.single.sharePositionOrigin, origin);
      expect(requests.single.files!.single.mimeType, 'image/png');
      expect(await requests.single.files!.single.readAsBytes(), preview.bytes);
      gate.complete(const ShareResult('', ShareResultStatus.dismissed));
      await tester.pumpAndSettle();
      expect(drafts.cleared, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(_icon('WhatsApp'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
    },
  );

  testWidgets(
    'fallo al compartir reintenta; selector tardío tras dispose no causa error',
    (tester) async {
      final gate = Completer<ShareResult>();
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: 'quotation-1',
            repository: FakeQuotationRepository(),
            shareTicket: (_) {
              if (++attempts == 1) throw StateError('plugin');
              return gate.future;
            },
          ),
        ),
      );
      await pumpReceiptImage(tester);
      await tester.tap(_icon('WhatsApp'));
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudo compartir la cotización. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      await tester.tap(_icon('WhatsApp'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      gate.completeError(StateError('cancelado'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'P27: estimación fallida permite reintentar sin generar ni limpiar',
    (tester) async {
      var attempts = 0;
      final repository = FakeQuotationRepository()
        ..estimateSource = (q) async {
          if (++attempts == 1) throw StateError('lectura');
          return sampleEstimate(q);
        };
      final drafts = FakeQuotationDraftCommands();
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: 'quotation-1',
            repository: repository,
            draftCommands: drafts,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No se pudo estimar. Reintentar'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.tap(find.text('No se pudo estimar. Reintentar'));
      await pumpReceiptImage(tester);
      expect(attempts, 2);
      expect(drafts.cleared, isEmpty);
    },
  );

  testWidgets(
    'P26/P27: estimación anterior tardía no reemplaza la nueva ni comparte importes viejos',
    (tester) async {
      final documents = StreamController<Quotation?>();
      addTearDown(documents.close);
      final old = Completer<QuotationEstimate>();
      final next = Completer<QuotationEstimate>();
      var estimates = 0;
      var drawings = 0;
      final repository = FakeQuotationRepository()
        ..documentSource = ((_) => documents.stream)
        ..estimateSource = (_) => ++estimates == 1 ? old.future : next.future;
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: 'quotation-1',
            repository: repository,
            generateImage: (ticket) {
              drawings++;
              return TicketImageGenerator().generate(ticket);
            },
          ),
        ),
      );
      documents.add(sampleQuotation());
      await tester.pump();
      await tester.pump();
      documents.add(sampleQuotation());
      await tester.pump();
      await tester.pump();
      expect(estimates, 2);
      expect(drawings, 0);
      next.complete(sampleEstimate(sampleQuotation(), piecePriceMinor: 12000));
      await pumpReceiptImage(tester);
      expect(
        tester.widget<Image>(find.byType(Image)).semanticLabel,
        contains(r'$415.00 MXN'),
      );
      old.complete(sampleEstimate(sampleQuotation()));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Image>(find.byType(Image)).semanticLabel,
        contains(r'$415.00 MXN'),
      );
      expect(drawings, 1);
    },
  );

  testWidgets(
    'P26/P27: rasterizado anterior tardío y fallo tras dispose son seguros',
    (tester) async {
      final documents = StreamController<Quotation?>();
      addTearDown(documents.close);
      final oldImage = Completer<Uint8List>();
      final lateImage = Completer<Uint8List>();
      var price = 3500;
      var drawings = 0;
      final repository = FakeQuotationRepository()
        ..documentSource = ((_) => documents.stream)
        ..estimateSource = (q) async =>
            sampleEstimate(q, piecePriceMinor: price);
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: 'quotation-1',
            repository: repository,
            generateImage: (ticket) {
              drawings++;
              if (drawings == 1) return oldImage.future;
              if (drawings == 3) return lateImage.future;
              return TicketImageGenerator().generate(ticket);
            },
          ),
        ),
      );
      documents.add(sampleQuotation());
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(drawings, 1);
      expect(tester.widget<IconButton>(_icon('Compartir')).onPressed, isNull);
      price = 12000;
      documents.add(sampleQuotation());
      await pumpReceiptImage(tester);
      final currentBytes =
          (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes;
      oldImage.completeError(StateError('dibujo anterior'));
      await tester.pumpAndSettle();
      expect(
        (tester.widget<Image>(find.byType(Image)).image as MemoryImage).bytes,
        currentBytes,
      );
      expect(
        tester.widget<Image>(find.byType(Image)).semanticLabel,
        contains(r'$415.00 MXN'),
      );
      price = 13000;
      documents.add(sampleQuotation());
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(drawings, 3);
      expect(find.byType(Image), findsNothing);
      expect(tester.widget<IconButton>(_icon('Compartir')).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      lateImage.completeError(StateError('dispose'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Nueva captura espera limpiar con revisión y bloquea compartir/doble limpieza',
    (tester) async {
      final gate = Completer<void>();
      final drafts = FakeQuotationDraftCommands()..gate = gate.future;
      await _openEmission(tester, drafts);
      await pumpReceiptImage(tester);
      await tester.tap(find.text('Nueva captura'));
      await tester.tap(find.text('Nueva captura'));
      await tester.pump();
      expect(drafts.cleared, hasLength(1));
      expect(drafts.cleared.single.expectedDraftEventId, 'draft-event');
      expect(find.byType(QuotationTicketScreen), findsOneWidget);
      expect(tester.widget<IconButton>(_icon('Compartir')).onPressed, isNull);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(QuotationTicketScreen), findsNothing);
    },
  );

  testWidgets(
    'revisión editada conserva captura y documento; limpieza tardía es segura',
    (tester) async {
      final drafts = FakeQuotationDraftCommands()
        ..error = StateError('La revisión del borrador cambió.');
      await _openEmission(tester, drafts);
      await pumpReceiptImage(tester);
      await tester.tap(find.text('Nueva captura'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('La cotización sigue guardada'),
        findsOneWidget,
      );
      expect(find.byType(QuotationTicketScreen), findsOneWidget);
      final gate = Completer<void>();
      drafts
        ..error = null
        ..gate = gate.future;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nueva captura'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dibujo fallido conserva documento y permite reintentar o nueva captura',
    (tester) async {
      final drafts = FakeQuotationDraftCommands();
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: 'quotation-1',
            repository: FakeQuotationRepository(),
            emissionDraft: const LimpiarVentaBorradorCommand(
              saleId: 'sale',
              expectedDraftEventId: 'draft-event',
            ),
            draftCommands: drafts,
            generateImage: (ticket) {
              if (++attempts == 1) throw StateError('raster');
              return TicketImageGenerator().generate(ticket);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('La cotización está guardada. No se pudo generar la imagen.'),
        findsOneWidget,
      );
      expect(drafts.cleared, isEmpty);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Nueva captura'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Reintentar'));
      await pumpReceiptImage(tester);
      expect(attempts, 2);
    },
  );

  testWidgets('histórico abre y cierra sin limpiar ninguna captura', (
    tester,
  ) async {
    final drafts = FakeQuotationDraftCommands();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Abrir'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => QuotationTicketScreen(
                    quotationId: 'quotation-1',
                    repository: FakeQuotationRepository(),
                    draftCommands: drafts,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await pumpReceiptImage(tester);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(drafts.cleared, isEmpty);
    expect(find.text('Abrir'), findsOneWidget);
  });

  testWidgets(
    'ticket muestra error/reintento y ausencia sin habilitar limpieza',
    (tester) async {
      final controller = StreamController<Quotation?>();
      addTearDown(controller.close);
      var calls = 0;
      final repository = FakeQuotationRepository()
        ..documentSource = (_) =>
            calls++ == 0 ? controller.stream : Stream.value(null);
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: 'absent',
            repository: repository,
            emissionDraft: const LimpiarVentaBorradorCommand(
              saleId: 'sale',
              expectedDraftEventId: 'event',
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      controller.addError(StateError('lectura'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('No se encontró la cotización.'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Nueva captura'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}

Future<void> _openEmission(
  WidgetTester tester,
  FakeQuotationDraftCommands drafts,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Abrir'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => QuotationTicketScreen(
                  quotationId: 'quotation-1',
                  repository: FakeQuotationRepository(),
                  draftCommands: drafts,
                  emissionDraft: const LimpiarVentaBorradorCommand(
                    saleId: 'sale',
                    expectedDraftEventId: 'draft-event',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
}

Finder _icon(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);
