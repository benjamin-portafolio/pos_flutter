import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_settings.dart';
import 'package:pos_flutter/application/printing/printer_test_payload.dart';

PrinterProfile make({
  String address = 'aa:bb:cc:dd:ee:01',
  String alias = ' Same name ',
  int width = 384,
}) => PrinterProfile(
  address: address,
  alias: alias,
  paper: PrinterPaper.mm58,
  printableWidthDots: width,
  imageCommand: PrinterImageCommand.gsV0,
);
void main() {
  test(
    'normalizes identity, retains explicit compatibility and validates input',
    () {
      final profile = make();
      expect(profile.address, 'AA:BB:CC:DD:EE:01');
      expect(profile.alias, 'Same name');
      expect(() => make(address: 'BlueTooth Printer'), throwsArgumentError);
      expect(() => make(alias: ' '), throwsArgumentError);
      expect(() => make(width: 383), throwsArgumentError);
      expect(() => make(width: 0), throwsArgumentError);
      expect(profile.supportsCut, isFalse);
    },
  );
  test(
    'multiple same-name profiles use distinct addresses and valid default',
    () {
      final a = make();
      final b = make(address: 'AA:BB:CC:DD:EE:02');
      final settings = PrinterSettings(
        printers: [a, b],
        defaultAddress: b.address,
      );
      expect(settings.printers, hasLength(2));
      expect(settings.defaultAddress, b.address);
      expect(() => settings.printers.clear(), throwsUnsupportedError);
      expect(() => PrinterSettings(printers: [a, a]), throwsArgumentError);
      expect(
        () => PrinterSettings(printers: [a], defaultAddress: b.address),
        throwsArgumentError,
      );
      expect(PrinterSettings(printers: []).defaultAddress, isNull);
    },
  );
  test(
    'calibration document identifies the profile and retains Spanish for raster',
    () {
      final document = PrinterTestPayload.create(make(alias: 'Prueba ñ'));
      expect(document.identifier, 'Prueba ñ');
      expect(document.details, contains('Dirección: AA:BB:CC:DD:EE:01'));
      expect(document.details, contains('Papel: 58 mm'));
      expect(document.details, contains('Ancho: 384 puntos'));
      expect(document.details, contains('Método: gsV0'));
      expect(document.footer, contains('ñ Ñ á é í ó ú ü'));
    },
  );
}
