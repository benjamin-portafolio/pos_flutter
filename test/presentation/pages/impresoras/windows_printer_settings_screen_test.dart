import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_settings_controller.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import 'package:pos_flutter/data/printing/windows_printer_gateway.dart';
import 'package:pos_flutter/presentation/pages/impresoras/printer_settings_screen.dart';
import '../../../support/fake_printer_settings_store.dart';
import '../../../support/fake_ticket_encoder.dart';

void main() {
  testWidgets(
    'Windows explicit discovery, add, default, edit, queue test and remove',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      final calls = <String>[];
      final gateway = WindowsPrinterGateway(
        isWindows: true,
        operation: (name, args) async {
          calls.add(name);
          return switch (name) {
            'list' => ['Pos-58'],
            'open' => <String, Object?>{'handle': 1, 'started': true},
            'finish' => <String, Object?>{'closed': true, 'failed': false},
            _ => null,
          };
        },
      );
      final settings = PrinterSettingsController(FakePrinterSettingsStore());
      final service = TicketPrintService(gateway, encoder: FakeTicketEncoder());
      await settings.load();
      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: PrinterSettingsScreen(
              controller: settings,
              gateway: gateway,
              printService: service,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        await tap('Agregar impresora');
        expect(find.text('Impresoras instaladas'), findsOneWidget);
        await tester.tap(find.byType(ListTile));
        await tester.pumpAndSettle();
        expect(find.text('Ancho imprimible (puntos)'), findsOneWidget);
        await tap('Guardar');
        expect(settings.settings.printers.single.address, 'Pos-58');
        expect(
          settings.settings.printers.single.transport,
          PrinterTransport.windowsSpooler,
        );
        await tap('Elegir predeterminada');
        expect(settings.settings.defaultAddress, 'windows:Pos-58');
        await tap('Editar');
        await tester.enterText(
          find.byType(TextFormField).first,
          'Caja Windows',
        );
        await tap('Guardar');
        expect(settings.settings.printers.single.alias, 'Caja Windows');
        await tap('Imprimir prueba');
        expect(
          find.textContaining('no confirma la impresión física'),
          findsOneWidget,
        );
        expect(calls.where((c) => c == 'open'), hasLength(1));
        await tap('Quitar');
        await tap('Quitar');
        expect(settings.settings.printers, isEmpty);
        expect(settings.settings.defaultAddress, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await service.dispose();
        await settings.dispose();
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
