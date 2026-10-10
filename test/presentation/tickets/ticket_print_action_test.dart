import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_exception.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_settings_controller.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import 'package:pos_flutter/application/tickets/ticket_document.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_estimate.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_line_estimate.dart';
import 'package:pos_flutter/domain/repositories/confirmed_sale_repository.dart';
import 'package:pos_flutter/domain/ventas/confirmed_sale.dart';
import 'package:pos_flutter/presentation/pages/caja/models/sale_receipt_display.dart';
import 'package:pos_flutter/presentation/pages/caja/sale_receipt_screen.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/models/quotation_display.dart';
import 'package:pos_flutter/presentation/pages/cotizaciones/quotation_ticket_screen.dart';
import 'package:pos_flutter/presentation/pages/impresoras/printer_settings_screen.dart';
import 'package:pos_flutter/presentation/tickets/ticket_print_action.dart';

import '../../support/fake_printer_gateway.dart';
import '../../support/fake_printer_settings_store.dart';
import '../../support/fake_ticket_encoder.dart';
import '../../support/pump_receipt_image.dart';
import '../../support/quotation_ui_fixtures.dart';
import '../../support/sale_draft_fixtures.dart';
import '../../support/thermal_ticket_fixtures.dart';

class _Sales implements ConfirmedSaleRepository {
  _Sales(this.sale);
  final ConfirmedSale sale;
  @override
  Stream<List<ConfirmedSale>> watchSales() => Stream.value([sale]);
}

Finder _print() =>
    find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Imprimir');

void main() {
  late PrinterSettingsController settings;
  late FakePrinterGateway gateway;
  late FakeTicketEncoder encoder;
  late TicketPrintService service;
  late ValueNotifier<TicketDocument?> visible;
  final a = thermalProfile();
  final b = thermalProfile(
    paper: PrinterPaper.mm80,
    address: 'AA:BB:CC:DD:EE:02',
  );

  void testPrinting(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      settings = PrinterSettingsController(FakePrinterSettingsStore());
      await settings.load();
      await settings.upsert(a);
      await settings.upsert(b);
      await settings.setDefault(a.address);
      gateway = FakePrinterGateway();
      encoder = FakeTicketEncoder();
      service = TicketPrintService(gateway, encoder: encoder);
      visible = ValueNotifier(thermalDocument());
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final gate in [
          encoder.pending,
          gateway.pendingWrite,
          gateway.pendingClose,
          gateway.pendingConnect,
        ]) {
          if (gate != null && !gate.isCompleted) gate.complete();
        }
        if (gateway.pendingPermission case final gate?) {
          if (!gate.isCompleted) gate.complete(PrinterPermission.granted);
        }
        await tester.pump();
        await service.dispose();
        await settings.dispose();
        visible.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: visible,
            builder: (_, document, _) => TicketPrintAction(
              document: document,
              controller: settings,
              gateway: gateway,
              service: service,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester) async {
    await tester.tap(_print());
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester) async {
    await select(tester);
    await tester.tap(find.text('Enviar ticket'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testPrinting(
    'default/paper shown; cancel does nothing; other destination is for one send',
    (tester) async {
      await open(tester);
      expect(gateway.calls, isEmpty);
      await select(tester);
      expect(find.text('Destino: A58'), findsOneWidget);
      expect(find.text('${a.address} · 58 mm'), findsOneWidget);
      expect(find.text('Predeterminada'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(encoder.documents, isEmpty);
      expect(gateway.calls, isEmpty);
      await select(tester);
      await tester.tap(find.text('Cambiar impresora'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B80'));
      await tester.pumpAndSettle();
      expect(find.text('Solo para este envío'), findsOneWidget);
      await tester.tap(find.text('Enviar ticket'));
      await tester.pumpAndSettle();
      expect(encoder.profiles.single, same(b));
      expect(settings.settings.defaultAddress, a.address);
      expect(
        find.textContaining('Ticket enviado a la impresora'),
        findsOneWidget,
      );
      expect(
        find.textContaining('no confirma la impresión física'),
        findsOneWidget,
      );
      await select(tester);
      expect(find.text('Destino: A58'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
    },
  );
  testPrinting(
    'without default requires explicit selection; deleting selected profile disables send',
    (tester) async {
      await settings.setDefault(null);
      await open(tester);
      await select(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enviar ticket'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('A58'));
      await tester.pumpAndSettle();
      await settings.remove(a.address);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enviar ticket'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(gateway.calls, isEmpty);
    },
  );
  testPrinting(
    'no profiles opens existing configuration without Bluetooth or sending',
    (tester) async {
      await settings.remove(a.address);
      await settings.remove(b.address);
      await open(tester);
      await select(tester);
      await tester.tap(find.text('Abrir configuración'));
      await tester.pumpAndSettle();
      expect(find.byType(PrinterSettingsScreen), findsOneWidget);
      expect(
        tester
            .widget<PrinterSettingsScreen>(find.byType(PrinterSettingsScreen))
            .printService,
        same(service),
      );
      expect(gateway.calls, isEmpty);
      expect(encoder.documents, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(gateway.calls, isEmpty);
    },
  );
  testPrinting(
    'confirmation captures latest visible doc/profile; later mutations and double touch cannot replace it',
    (tester) async {
      await open(tester);
      await select(tester);
      final confirmed = thermalDocument(lines: 6);
      visible.value = confirmed;
      final edited = thermalProfile(width: 376, alias: 'Editada');
      await settings.upsert(edited);
      await tester.pumpAndSettle();
      expect(find.text('Destino: Editada'), findsOneWidget);
      encoder.pending = Completer<void>();
      await tester.tap(find.text('Enviar ticket'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(service.isBusy, isTrue);
      final button = tester.widget<IconButton>(_print());
      expect(button.onPressed, isNull);
      expect(
        find.textContaining('Preparando y enviando a Editada'),
        findsOneWidget,
      );
      visible.value = thermalDocument(lines: 9);
      await settings.upsert(a);
      await tester.pump();
      expect((await service.printTest(b)).failure, PrinterFailure.busy);
      encoder.pending!.complete();
      await tester.pumpAndSettle();
      expect(encoder.documents.single, same(confirmed));
      expect(encoder.profiles.single, same(edited));
      expect(
        gateway.calls.where((c) => c.startsWith('connect:')),
        hasLength(1),
      );
    },
  );
  testPrinting(
    'permission pending and route closed: no late send or UI callback',
    (tester) async {
      gateway.permission = PrinterPermission.denied;
      gateway.pendingPermission = Completer<PrinterPermission>();
      await open(tester);
      await send(tester);
      expect(service.isBusy, isTrue);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gateway.pendingPermission!.complete(PrinterPermission.granted);
      await tester.pumpAndSettle();
      expect(encoder.documents, isEmpty);
      expect(gateway.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testPrinting(
    'permission deadline owns late preflight until native permission finishes',
    (tester) async {
      service = TicketPrintService(
        gateway,
        encoder: encoder,
        permissionTimeout: const Duration(milliseconds: 10),
      );
      gateway.permission = PrinterPermission.denied;
      gateway.pendingPermission = Completer<PrinterPermission>();
      await open(tester);
      await send(tester);
      expect(
        find.textContaining('Se agotó el tiempo de espera'),
        findsOneWidget,
      );
      // More than the helper's usual 35 seconds: the native future is still owned.
      await tester.pump(const Duration(seconds: 36));
      expect(service.isBusy, isTrue);
      expect((await service.printTest(b)).failure, PrinterFailure.busy);
      expect(tester.widget<IconButton>(_print()).onPressed, isNull);
      gateway.pendingPermission!.complete(PrinterPermission.granted);
      await tester.pumpAndSettle();
      expect(service.isBusy, isFalse);
      expect(gateway.writes, isEmpty);
      expect(gateway.calls.where((c) => c.startsWith('connect:')), isEmpty);
    },
  );
  testPrinting(
    'background invalidates pending permission; resume never prints automatically',
    (tester) async {
      gateway.permission = PrinterPermission.denied;
      gateway.pendingPermission = Completer<PrinterPermission>();
      await open(tester);
      await send(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gateway.pendingPermission!.complete(PrinterPermission.granted);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(gateway.writes, isEmpty);
      expect(service.isBusy, isFalse);
      expect(tester.widget<IconButton>(_print()).onPressed, isNotNull);
    },
  );
  testPrinting(
    'closing during generation cancels before connect; closing during write keeps single job cleanup',
    (tester) async {
      encoder.pending = Completer<void>();
      await open(tester);
      await send(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      encoder.pending!.complete();
      await tester.pumpAndSettle();
      expect(gateway.writes, isEmpty);
      encoder.pending = null;
      gateway.pendingWrite = Completer<void>();
      await open(tester);
      await send(tester);
      expect(gateway.writes, hasLength(1));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gateway.pendingWrite!.complete();
      await tester.pumpAndSettle();
      expect(gateway.writes, hasLength(3));
      expect(gateway.calls.where((c) => c == 'close'), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testPrinting('partial failure warns; reprint requires a new manual action', (
    tester,
  ) async {
    gateway.writeFailure = PrinterFailure.writeFailed;
    await open(tester);
    await send(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Puede haberse impreso una parte'),
      findsOneWidget,
    );
    expect(encoder.documents, hasLength(1));
    gateway.writeFailure = null;
    await tester.pump();
    expect(encoder.documents, hasLength(1));
    await send(tester);
    await tester.pumpAndSettle();
    expect(encoder.documents, hasLength(2));
  });
  testPrinting(
    'busy configuration probe disables ticket action until native close finishes',
    (tester) async {
      gateway.pendingWrite = Completer<void>();
      gateway.pendingClose = Completer<void>();
      await open(tester);
      final probe = service.printTest(a);
      await tester.pump();
      expect(tester.widget<IconButton>(_print()).onPressed, isNull);
      gateway.pendingWrite!.complete();
      await tester.pump();
      expect(tester.widget<IconButton>(_print()).onPressed, isNull);
      gateway.pendingClose!.complete();
      await probe;
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(_print()).onPressed, isNotNull);
      expect(encoder.documents, hasLength(1)); // Only the calibration probe.
      expect(encoder.documents.single.title, 'PRUEBA DE IMPRESIÓN');
    },
  );
  testPrinting(
    'unavailable platform explains limitation and never calls gateway/plugin',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await open(tester);
      expect(tester.widget<IconButton>(_print()).onPressed, isNull);
      expect(
        find.text('Impresión disponible en Android y Windows.'),
        findsOneWidget,
      );
      expect(gateway.calls, isEmpty);
    },
  );
  testPrinting('no document keeps print disabled', (tester) async {
    visible.value = null;
    await open(tester);
    expect(tester.widget<IconButton>(_print()).onPressed, isNull);
    expect(gateway.calls, isEmpty);
  });

  for (final method in ['cash', 'transfer', 'credit']) {
    testPrinting(
      'sale screen prints confirmed $method snapshot and permits manual reprint',
      (tester) async {
        final sale = ConfirmedSale(
          id: 'confirmed-$method',
          createdAt: DateTime(2026, 10, 9),
          totalMinor: sampleSale().totalMinor,
          receivedMinor: sampleSale().totalMinor + 100,
          changeMinor: 100,
          currency: 'MXN',
          paymentMethod: method,
          paymentReference: method == 'transfer' ? 'SPEI-123' : null,
          clienteNombre: method == 'credit' ? 'María Muñoz' : null,
          deliveryStatus: 'not_required',
          reason: null,
          items: sampleSale().items,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SaleReceiptScreen(
              saleId: sale.id,
              repository: _Sales(sale),
              printerSettings: settings,
              printerGateway: gateway,
              printService: service,
            ),
          ),
        );
        await pumpReceiptImage(tester);
        expect(encoder.documents, isEmpty);
        await send(tester);
        await tester.pumpAndSettle();
        final expected = SaleReceiptDisplay(sale).ticket;
        final captured = encoder.documents.single;
        expect(captured.itemRows, expected.itemRows);
        expect(captured.totals, expected.totals);
        expect(captured.summary, expected.summary);
        expect(captured.details, expected.details);
        await send(tester);
        await tester.pumpAndSettle();
        expect(encoder.documents, hasLength(2));
        expect(encoder.documents.last.itemRows, captured.itemRows);
      },
    );
  }
  testPrinting(
    'quotation freezes displayed prices/date/legend across later price publication',
    (tester) async {
      final stream = StreamController<Quotation>();
      final original = sampleQuotation();
      var price = 3500;
      final repository = FakeQuotationRepository();
      repository.documentSource = (_) => stream.stream;
      repository.estimateSource = (q) async =>
          sampleEstimate(q, piecePriceMinor: price);
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: original.id,
            repository: repository,
            printerSettings: settings,
            printerGateway: gateway,
            printService: service,
          ),
        ),
      );
      stream.add(original);
      await pumpReceiptImage(tester);
      final expected = QuotationDisplay(
        original,
        sampleEstimate(original),
      ).ticket;
      encoder.pending = Completer<void>();
      await send(tester);
      price = 9900;
      stream.add(sampleQuotation());
      await tester.pump();
      encoder.pending!.complete();
      await tester.pump();
      // The visible preview can update; the encoder owns the earlier document.
      expect(encoder.documents.single.itemRows, expected.itemRows);
      expect(encoder.documents.single.details, expected.details);
      expect(encoder.documents.single.footer, expected.footer);
      await pumpReceiptImage(tester);
      expect(gateway.writes, hasLength(3));
      expect(
        find.textContaining('Ticket enviado a la impresora'),
        findsOneWidget,
      );
      await stream.close();
    },
  );
  testPrinting(
    'quotation missing prices prints unavailable strings unchanged without persistence',
    (tester) async {
      final quotation = sampleQuotation();
      final repository = FakeQuotationRepository([quotation])
        ..estimateSource = (_) async => QuotationEstimate(
          calculatedAt: DateTime(2026, 10, 9),
          totalMinor: null,
          lines: [
            for (final item in quotation.items)
              QuotationLineEstimate(
                quotationItemId: item.id,
                unitPriceMinor: null,
                priceReferenceQuantityAtomic: null,
                totalMinor: null,
                issue: 'Precio pendiente',
              ),
          ],
        );
      await tester.pumpWidget(
        MaterialApp(
          home: QuotationTicketScreen(
            quotationId: quotation.id,
            repository: repository,
            printerSettings: settings,
            printerGateway: gateway,
            printService: service,
          ),
        ),
      );
      await pumpReceiptImage(tester);
      await send(tester);
      await tester.pumpAndSettle();
      final captured = encoder.documents.single;
      expect(
        captured.itemRows.every(
          (r) =>
              r[1] == 'Precio no disponible' && r[3] == 'Importe no disponible',
        ),
        isTrue,
      );
      expect(captured.totals.single.$2, 'Total no disponible');
      expect(captured.footer, QuotationDisplay.legend);
      expect(repository.documents.single, same(quotation));
    },
  );
}
