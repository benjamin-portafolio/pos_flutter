import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pos_flutter/application/tickets/supplier_document_ticket.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_document_screen.dart';
import 'package:pos_flutter/presentation/tickets/ticket_image_generator.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';
import 'package:pos_flutter/application/printing/printer_settings_controller.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import '../../../../support/fake_printer_gateway.dart';
import '../../../../support/fake_printer_settings_store.dart';
import '../../../../support/fake_ticket_encoder.dart';
import '../../../../support/thermal_ticket_fixtures.dart';
import '../../../../support/product_supplier_harness.dart';
import '../../../../support/pump_receipt_image.dart';
import '../../../../support/supplier_order_harness.dart';
import '../../../../application/commands/proveedores/supplier_receipt_local_test.dart'
    show confirmedOrder, receipt;

Future<void> finish(WidgetTester t, Future<void> future) async {
  var done = false;
  final result = future.whenComplete(() => done = true);
  for (var i = 0; i < 100 && !done; i++) {
    await t.pump(const Duration(milliseconds: 20));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(
    done,
    isTrue,
    reason: 'Cleanup must complete after widget subscriptions are removed.',
  );
  await result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['POS_S5_VISUAL_DIR'] != null) {
      final font = FontLoader('Roboto')
        ..addFont(
          File(
            '/System/Library/Fonts/Supplemental/Arial.ttf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(
          File(
            'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
          ).readAsBytes().then((v) => ByteData.sublistView(v)),
        );
      await icons.load();
    }
  });
  test(
    'S5 snapshots: tickets pedido/recepción, acumulado causal, unidades y catálogo cambiado',
    () async {
      final h = ProductSupplierHarness();
      try {
        final id = await confirmedOrder(h);
        final repo = DriftSupplierOrderRepository(h.db);
        await h.orders.receive(await receipt(h, id, 3, price: 1250));
        final first = (await repo.readDetail(id))!;
        final order = SupplierDocumentTicket.build(first),
            actual = SupplierDocumentTicket.build(
              first,
              receipt: first.receipts.single,
            );
        expect(order.itemRows.single, [
          'Café',
          '35.01 / 1 pza',
          '4 pza',
          '140.04',
        ]);
        expect(actual.itemRows.single, [
          'Café',
          '12.50 / 1 pza',
          '3 pza',
          '37.50',
        ]);
        expect(actual.totals.last.$2, '37.50');
        await h.orders.receive(await receipt(h, id, 1, price: 100));
        await h.db.customUpdate("UPDATE products SET name='Nombre posterior'");
        await h.db.customUpdate(
          "UPDATE suppliers SET name='Proveedor posterior'",
        );
        final after = (await repo.readDetail(id))!;
        final repeated = SupplierDocumentTicket.build(
          after,
          receipt: after.receipts.first,
        );
        expect(repeated.itemRows, actual.itemRows);
        expect(repeated.totals, actual.totals);
        expect(repeated.details, actual.details);
        expect(after.receivedTotal, 3850);
        final bytes = await TicketImageGenerator().generate(repeated);
        expect(bytes.length, greaterThan(1000));
        final dir = Platform.environment['POS_S5_VISUAL_DIR'];
        if (dir != null) {
          await Directory(dir).create(recursive: true);
          await File('$dir/ticket-recepcion.png').writeAsBytes(bytes);
          await File(
            '$dir/ticket-pedido.png',
          ).writeAsBytes(await TicketImageGenerator().generate(order));
        }
      } finally {
        await h.dispose();
      }
    },
  );
  testWidgets(
    'S5 compartir cancelar/error/reintento y reimpresión conservan documento y negocio',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final h = ProductSupplierHarness();
      final id = (await t.runAsync(() => confirmedOrder(h)))!;
      await h.orders.receive(await receipt(h, id, 3, price: 1250));
      final detail = (await DriftSupplierOrderRepository(h.db).readDetail(id))!;
      final document = SupplierDocumentTicket.build(
        detail,
        receipt: detail.receipts.single,
      );
      final settings = PrinterSettingsController(FakePrinterSettingsStore());
      await settings.load();
      final profile = thermalProfile();
      await settings.upsert(profile);
      await settings.setDefault(profile.address);
      final gateway = FakePrinterGateway(), encoder = FakeTicketEncoder();
      final service = TicketPrintService(gateway, encoder: encoder);
      getIt.registerSingleton<PrinterSettingsController>(settings);
      getIt.registerSingleton<PrinterGateway>(gateway);
      getIt.registerSingleton<TicketPrintService>(service);
      final events = (await h.db.select(h.db.events).get()).length;
      final shared = <Uint8List>[];
      var generation = 0;
      final statuses = StreamController<String>();
      try {
        final image = await t.runAsync(
          () => TicketImageGenerator().generate(document),
        );
        await t.pumpWidget(
          MaterialApp(
            home: SupplierDocumentScreen(
              document: document,
              initialStatus: 'pending',
              statusUpdates: statuses.stream,
              generateImage: (d) async {
                expect(d, same(document));
                if (generation++ == 0) throw StateError('imagen');
                return image!;
              },
              shareTicket: (params) async {
                shared.add(await params.files!.single.readAsBytes());
                if (shared.length == 1) throw StateError('selector');
                return const ShareResult('', ShareResultStatus.dismissed);
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('No se pudo generar la imagen. Reintentar'));
        await t.pumpAndSettle();
        await pumpReceiptImage(t);
        await t.tap(find.text('Compartir'));
        await t.pumpAndSettle();
        expect(find.textContaining('No se pudo compartir'), findsOneWidget);
        await t.tap(find.text('Compartir'));
        await t.pumpAndSettle();
        expect(shared.length, 2);
        expect(shared[0], shared[1]);
        for (var i = 0; i < 2; i++) {
          await t.tap(find.byTooltip('Imprimir'));
          await t.pumpAndSettle();
          await t.tap(find.text('Enviar ticket'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 300));
          await t.pumpAndSettle();
          expect(service.isBusy, isFalse);
        }
        expect(encoder.documents.length, 2);
        expect(encoder.documents.every((d) => identical(d, document)), isTrue);
        expect((await h.db.select(h.db.events).get()).length, events);
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .single
              .quantityOnHandAtomic,
          6,
        );
        expect((await h.db.select(h.db.supplierReceipts).get()).length, 1);

        statuses.add('rejected');
        await t.pumpAndSettle();
        expect(
          find.textContaining('La recepción seleccionada fue rechazada'),
          findsOneWidget,
        );
        expect(
          t
              .widget<TextButton>(
                find.ancestor(
                  of: find.text('Compartir'),
                  matching: find.byType(TextButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(shared.length, 2);
      } finally {
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();

        await finish(t, statuses.close());

        await finish(t, service.dispose());

        await finish(t, settings.dispose());

        await t.runAsync(h.dispose);
        await getIt.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
