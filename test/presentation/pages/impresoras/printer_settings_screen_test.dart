import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_device.dart';
import 'package:pos_flutter/application/printing/printer_exception.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_settings_controller.dart';
import 'package:pos_flutter/application/printing/printer_settings_exception.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import 'package:pos_flutter/presentation/pages/impresoras/bonded_printers_screen.dart';
import 'package:pos_flutter/presentation/pages/impresoras/printer_settings_screen.dart';

import '../../../support/fake_printer_gateway.dart';
import '../../../support/fake_printer_settings_store.dart';
import '../../../support/fake_ticket_encoder.dart';

void main() {
  late FakePrinterSettingsStore store;
  late PrinterSettingsController controller;
  late FakePrinterGateway gateway;
  late TicketPrintService service;
  late FakeTicketEncoder encoder;
  final a = PrinterProfile(
    address: 'AA:BB:CC:DD:EE:01',
    alias: 'A58',
    paper: PrinterPaper.mm58,
    printableWidthDots: 384,
    imageCommand: PrinterImageCommand.escStar,
  );
  final b = PrinterProfile(
    address: 'AA:BB:CC:DD:EE:02',
    alias: 'B80',
    paper: PrinterPaper.mm80,
    printableWidthDots: 576,
    imageCommand: PrinterImageCommand.gsL,
  );
  Future<void> initialize() async {
    store = FakePrinterSettingsStore();
    controller = PrinterSettingsController(store);
    await controller.load();
    gateway = FakePrinterGateway();
    encoder = FakeTicketEncoder()
      ..source = (() async* {
        yield [27, 64, 65, 10];
      });
    service = TicketPrintService(gateway, encoder: encoder);
  }

  void testPrinterWidgets(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      await initialize();
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final pending in [
          gateway.pendingWrite,
          gateway.pendingClose,
          gateway.pendingConnect,
        ]) {
          if (pending != null && !pending.isCompleted) pending.complete();
        }
        if (gateway.pendingPermission case final pending?) {
          if (!pending.isCompleted) pending.complete(PrinterPermission.granted);
        }
        await service.dispose();
        await controller.dispose();
      }
    });
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrinterSettingsScreen(
          controller: controller,
          gateway: gateway,
          printService: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder action(String address, String label) => find.descendant(
    of: find.byKey(ValueKey(address)),
    matching: find.text(label),
  );
  Future<void> seed() async {
    await controller.upsert(a);
    await controller.upsert(b);
    await controller.setDefault(a.address);
  }

  testPrinterWidgets(
    'opening configuration never requests Bluetooth and add shows names/addresses',
    (tester) async {
      await open(tester);
      expect(gateway.calls, isEmpty);
      await tap(tester, find.text('Agregar impresora'));
      expect(find.text('Same name'), findsNWidgets(2));
      expect(find.text(a.address), findsOneWidget);
      expect(find.text(b.address), findsOneWidget);
      expect(find.textContaining('Ajustes del sistema'), findsOneWidget);
      expect(gateway.calls.where((c) => c.startsWith('connect')), isEmpty);
      await tap(tester, find.text(a.address));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Alias'),
        'Mi impresora',
      );
      await tap(tester, find.text('Guardar'));
      expect(controller.settings.printers.single.alias, 'Mi impresora');
      expect(controller.settings.defaultAddress, isNull);
      expect(controller.settings.printers.single.supportsCut, isFalse);
    },
  );

  testPrinterWidgets(
    'save same address edits; equal names create separate profiles; cancel is inert',
    (tester) async {
      await controller.upsert(a);
      await open(tester);
      await tap(tester, find.text('Agregar impresora'));
      await tap(tester, find.text(a.address));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Alias'),
        'Canceled',
      );
      await tap(tester, find.text('Cancelar'));
      expect(controller.settings.printers.single.alias, 'A58');
      await tap(tester, find.text('Agregar impresora'));
      await tap(tester, find.text(a.address));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Alias'),
        'Same name',
      );
      await tap(tester, find.text('Guardar'));
      expect(controller.settings.printers, hasLength(1));
      await tap(tester, find.text('Agregar impresora'));
      await tap(tester, find.text(b.address));
      await tap(tester, find.text('Guardar'));
      expect(controller.settings.printers, hasLength(2));
      expect(controller.settings.printers.map((p) => p.alias), [
        'Same name',
        'Same name',
      ]);
    },
  );

  testPrinterWidgets(
    'edit paper, preserve compatibility on alias edit, validate and cancel',
    (tester) async {
      await controller.upsert(a);
      await open(tester);
      await tap(tester, action(a.address, 'Editar'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Alias'), '  ');
      await tap(tester, find.text('Guardar'));
      expect(find.text('Escribe un alias.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Alias'),
        'Changed',
      );
      await tap(tester, find.text('58 mm').last);
      await tap(tester, find.text('80 mm').last);
      await tap(tester, find.text('Guardar'));
      final edited = controller.settings.printers.single;
      expect(edited.paper, PrinterPaper.mm80);
      expect(edited.printableWidthDots, 576);
      expect(edited.imageCommand, PrinterImageCommand.escStar);
      expect(edited.supportsCut, isFalse);
      await tap(tester, action(a.address, 'Editar'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Alias'),
        'Canceled',
      );
      await tap(tester, find.text('Cancelar'));
      expect(controller.settings.printers.single, same(edited));
    },
  );

  testPrinterWidgets(
    'choose and clear default; remove only from app and no silent replacement',
    (tester) async {
      await seed();
      await open(tester);
      await tap(tester, action(b.address, 'Elegir predeterminada'));
      expect(controller.settings.defaultAddress, b.address);
      await tap(tester, find.text('Dejar sin predeterminada'));
      expect(controller.settings.defaultAddress, isNull);
      await tap(tester, action(a.address, 'Elegir predeterminada'));
      await tap(tester, action(a.address, 'Quitar'));
      expect(
        find.textContaining('seguirá disponible en el sistema'),
        findsOneWidget,
      );
      await tap(tester, find.text('Cancelar'));
      expect(controller.settings.printers, hasLength(2));
      await tap(tester, action(a.address, 'Quitar'));
      await tap(tester, find.widgetWithText(FilledButton, 'Quitar'));
      expect(controller.settings.defaultAddress, isNull);
      expect(controller.settings.printers.single, same(b));
      expect(gateway.calls, isEmpty);
    },
  );

  for (final permission in [
    PrinterPermission.denied,
    PrinterPermission.permanentlyDenied,
  ]) {
    testPrinterWidgets(
      'permission $permission is actionable; reload after grant',
      (tester) async {
        gateway.permission = permission;
        gateway.requestedPermission = permission;
        await open(tester);
        await tap(tester, find.text('Agregar impresora'));
        expect(find.textContaining('Permiso Bluetooth'), findsOneWidget);
        expect(gateway.calls.contains('bondedDevices'), isFalse);
        if (permission == PrinterPermission.permanentlyDenied) {
          expect(gateway.calls.contains('requestPermission'), isFalse);
        }
        gateway.permission = PrinterPermission.granted;
        await tap(tester, find.text('Recargar'));
        expect(find.text(a.address), findsOneWidget);
      },
    );
  }

  for (final state in [
    PrinterAvailability.off,
    PrinterAvailability.unsupported,
    PrinterAvailability.noHardware,
  ]) {
    testPrinterWidgets(
      'availability $state keeps page responsive without requesting permissions',
      (tester) async {
        gateway.state = state;
        await open(tester);
        await tap(tester, find.text('Agregar impresora'));
        expect(find.byType(BondedPrintersScreen), findsOneWidget);
        expect(gateway.calls, ['availability']);
        gateway.state = PrinterAvailability.ready;
        gateway.devices = [];
        await tap(tester, find.text('Recargar'));
        expect(find.text('No hay dispositivos vinculados.'), findsOneWidget);
        gateway.devices = [
          PrinterDevice(address: a.address, name: 'Now paired'),
        ];
        await tap(tester, find.text('Recargar'));
        expect(find.text('Now paired'), findsOneWidget);
      },
    );
  }

  testPrinterWidgets(
    'pending permission on listing is ignored after closing route',
    (tester) async {
      gateway.permission = PrinterPermission.denied;
      gateway.pendingPermission = Completer<PrinterPermission>();
      await open(tester);
      await tester.tap(find.text('Agregar impresora'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(gateway.calls, contains('requestPermission'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      gateway.pendingPermission!.complete(PrinterPermission.granted);
      await tester.pumpAndSettle();
      expect(gateway.calls, isNot(contains('bondedDevices')));
      expect(tester.takeException(), isNull);
    },
  );

  testPrinterWidgets(
    'A58 → B80 → A58 uses captured profiles without changing default',
    (tester) async {
      await seed();
      await open(tester);
      for (final profile in [a, b, a]) {
        await tap(tester, action(profile.address, 'Imprimir prueba'));
        expect(find.textContaining('Prueba enviada a'), findsOneWidget);
        expect(
          find.textContaining('no confirma la impresión física'),
          findsOneWidget,
        );
        expect(
          encoder.documents.last.details.join('\n'),
          contains('${profile.printableWidthDots} puntos'),
        );
        expect(
          encoder.documents.last.details.join('\n'),
          contains(profile.address),
        );
        expect(encoder.profiles.last, same(profile));
        expect(controller.settings.defaultAddress, a.address);
      }
      expect(gateway.calls.where((c) => c.startsWith('connect:')), [
        'connect:${a.address}',
        'connect:${b.address}',
        'connect:${a.address}',
      ]);
      expect(gateway.calls.where((c) => c == 'close'), hasLength(3));
      expect(store.writes, 3);
    },
  );

  testPrinterWidgets(
    'global busy rejects UI print; no queue; write failure warns possible partial output',
    (tester) async {
      await seed();
      gateway.pendingWrite = Completer<void>();
      final otherPrint = service.printTest(a);
      await open(tester);
      await tap(tester, action(b.address, 'Imprimir prueba'));
      expect(
        find.textContaining('servicio de impresión está ocupado'),
        findsOneWidget,
      );
      expect(gateway.writes, hasLength(1));
      gateway.pendingWrite!.complete();
      await otherPrint;
      gateway.pendingWrite = null;
      gateway.writeFailure = PrinterFailure.writeFailed;
      await tap(tester, action(b.address, 'Imprimir prueba'));
      expect(
        find.textContaining('Puede haberse impreso una parte'),
        findsOneWidget,
      );
      expect(gateway.writes, hasLength(2));
      expect(gateway.calls.where((c) => c == 'close'), hasLength(2));
    },
  );

  testPrinterWidgets(
    'progress disables repeat print and closing during write ignores callbacks',
    (tester) async {
      await seed();
      gateway.pendingWrite = Completer<void>();
      await open(tester);
      await tester.tap(action(a.address, 'Imprimir prueba'));
      await tester.pump();
      expect(find.textContaining('Enviando prueba a'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.ancestor(
                of: action(b.address, 'Imprimir prueba'),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gateway.pendingWrite!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(gateway.writes, hasLength(1));
      expect(service.isBusy, isFalse);
      expect(gateway.calls, contains('close'));
    },
  );

  testPrinterWidgets(
    'closing during test permission prevents a late connection or send',
    (tester) async {
      await controller.upsert(a);
      gateway.permission = PrinterPermission.denied;
      gateway.pendingPermission = Completer<PrinterPermission>();
      await open(tester);
      await tester.tap(action(a.address, 'Imprimir prueba'));
      await tester.pump();
      expect(gateway.calls, contains('requestPermission'));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      gateway.pendingPermission!.complete(PrinterPermission.granted);
      await tester.pumpAndSettle();
      expect(gateway.writes, isEmpty);
      expect(gateway.calls.any((c) => c.startsWith('connect:')), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testPrinterWidgets('failed profile save does not publish edits to screen', (
    tester,
  ) async {
    await controller.upsert(a);
    await open(tester);
    store.failWrite = true;
    await tap(tester, action(a.address, 'Editar'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Alias'),
      'Unsaved',
    );
    await tap(tester, find.text('Guardar'));
    expect(find.text('A58'), findsOneWidget);
    expect(find.text('Unsaved'), findsNothing);
    expect(find.textContaining('último estado confirmado'), findsOneWidget);
  });

  testPrinterWidgets(
    'corruption warning and explicit recovery with cancel preserve configuration',
    (tester) async {
      store.readError = const PrinterSettingsException(
        PrinterSettingsFailure.corrupt,
      );
      await controller.load();
      await open(tester);
      expect(
        find.textContaining('archivo de impresoras está dañado'),
        findsOneWidget,
      );
      await tap(tester, find.text('Recuperar configuración'));
      await tap(tester, find.text('Cancelar'));
      expect(store.recoveries, 0);
      await tap(tester, find.text('Recuperar configuración'));
      await tap(tester, find.text('Conservar y reiniciar'));
      expect(store.recoveries, 1);
      expect(find.text('No hay impresoras guardadas.'), findsOneWidget);
      expect(find.textContaining('Original conservado'), findsOneWidget);
      expect(gateway.calls, isEmpty);
    },
  );
}
