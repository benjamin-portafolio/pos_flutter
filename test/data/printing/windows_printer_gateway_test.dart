import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_exception.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_settings_controller.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import 'package:pos_flutter/data/local/printing/printer_settings_file_store.dart';
import 'package:pos_flutter/data/printing/android_bluetooth_printer_gateway.dart';
import 'package:pos_flutter/data/printing/printer_gateway_factory.dart';
import 'package:pos_flutter/data/printing/windows_printer_gateway.dart';

PrinterProfile windowsProfile([String name = 'Pos-58']) => PrinterProfile(
  address: name,
  transport: PrinterTransport.windowsSpooler,
  alias: 'Caja',
  paper: PrinterPaper.mm58,
  printableWidthDots: 384,
  imageCommand: PrinterImageCommand.gsV0,
);

void main() {
  test(
    'Windows name preserves case and requires no MAC; keys isolate transports',
    () {
      final profile = windowsProfile();
      expect(profile.address, 'Pos-58');
      expect(profile.destinationKey, 'windows:Pos-58');
      expect(() => windowsProfile(''), throwsArgumentError);
      expect(() => windowsProfile('POS\u000058'), throwsArgumentError);
    },
  );
  test('factory selects platform without native operations', () {
    expect(
      createPrinterGateway(platform: TargetPlatform.windows, isWeb: false),
      isA<WindowsPrinterGateway>(),
    );
    expect(
      createPrinterGateway(platform: TargetPlatform.android, isWeb: false),
      isA<AndroidBluetoothPrinterGateway>(),
    );
    expect(
      createPrinterGateway(platform: TargetPlatform.windows, isWeb: true),
      isA<AndroidBluetoothPrinterGateway>(),
    );
  });
  test(
    'version 1 explicitly loads Bluetooth and saves mixed v2 profiles/default',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'windows_printer_settings',
      );
      final store = PrinterSettingsFileStore(
        directoryProvider: () async => dir,
      );
      final file = File('${dir.path}/printer_settings.json');
      final controller = PrinterSettingsController(store);
      try {
        await file.writeAsString(
          jsonEncode({
            'version': 1,
            'defaultAddress': 'aa:bb:cc:dd:ee:01',
            'printers': [
              {
                'address': 'aa:bb:cc:dd:ee:01',
                'alias': 'Old',
                'paper': 'mm58',
                'printableWidthDots': 384,
                'imageCommand': 'escStar',
                'supportsCut': false,
              },
            ],
          }),
        );
        await controller.load();
        expect(
          controller.settings.printers.single.transport,
          PrinterTransport.androidBluetooth,
        );
        expect(controller.settings.defaultAddress, 'AA:BB:CC:DD:EE:01');
        final profile = windowsProfile();
        await controller.upsert(profile);
        await controller.setDefault(profile.destinationKey);
        final read = await store.readSettings();
        expect(read.printers.last.address, 'Pos-58');
        expect(read.printers.last.transport, PrinterTransport.windowsSpooler);
        expect(read.defaultAddress, profile.destinationKey);
        expect(jsonDecode(await file.readAsString())['version'], 2);
        await controller.remove(profile.destinationKey);
        expect(controller.settings.defaultAddress, isNull);
        expect(controller.settings.printers.single.alias, 'Old');
      } finally {
        await controller.dispose();
        await dir.delete(recursive: true);
      }
    },
  );

  late List<String> calls;
  late List<Map<String, Object?>> arguments;
  late WindowsPrinterGateway gateway;
  Future<Object?> operation(String name, Map<String, Object?> args) async {
    calls.add(name);
    arguments.add(args);
    return switch (name) {
      'list' => ['Pos-58'],
      'open' => <String, Object?>{'handle': 123, 'started': true},
      'finish' => <String, Object?>{'closed': true, 'failed': false},
      _ => null,
    };
  }

  setUp(() {
    calls = [];
    arguments = [];
    gateway = WindowsPrinterGateway(operation: operation, isWindows: true);
  });
  test(
    'one RAW document for all writes; finish acknowledges queue only',
    () async {
      expect(
        (await gateway.listDestinations()).single.transport,
        PrinterTransport.windowsSpooler,
      );
      await gateway.connect('Pos-58');
      await gateway.write([27, 64]);
      await gateway.write([10]);
      await gateway.finishJob(commit: true);
      await gateway.close();
      expect(calls, ['list', 'open', 'write', 'write', 'finish']);
      expect(arguments[1]['name'], 'Pos-58');
      expect(arguments.last['commit'], true);
    },
  );
  test('service errors abort job without retry', () async {
    gateway = WindowsPrinterGateway(
      isWindows: true,
      operation: (name, args) async {
        if (name == 'write') {
          calls.add(name);
          throw const PrinterException(PrinterFailure.writeFailed);
        }
        return operation(name, args);
      },
    );
    final service = TicketPrintService(gateway);
    final result = await service.send(profile: windowsProfile(), bytes: [10]);
    expect(result.failure, PrinterFailure.writeFailed);
    expect(result.mayHavePrinted, true);
    expect(calls, ['list', 'open', 'write', 'finish']);
    expect(arguments.last['commit'], false);
    expect(service.isBusy, false);
    await service.dispose();
  });
  test('open failure retains handle for cleanup; no writes', () async {
    gateway = WindowsPrinterGateway(
      isWindows: true,
      operation: (name, args) async {
        if (name == 'open') {
          return <String, Object?>{'handle': 123, 'started': false};
        }
        return operation(name, args);
      },
    );
    await expectLater(
      gateway.connect('Pos-58'),
      throwsA(isA<PrinterException>()),
    );
    await gateway.close();
    expect(arguments.last['documentOpen'], false);
  });
  test(
    'failed finalization never repeats EndDoc; close failure retains ownership',
    () async {
      gateway = WindowsPrinterGateway(
        isWindows: true,
        operation: (name, args) async {
          if (name == 'finish') {
            calls.add(name);
            arguments.add(args);
            return <String, Object?>{
              'closed': calls.where((c) => c == 'finish').length > 1,
              'failed': true,
            };
          }
          return operation(name, args);
        },
      );
      await gateway.connect('Pos-58');
      await expectLater(
        gateway.finishJob(commit: true),
        throwsA(isA<PrinterException>()),
      );
      await expectLater(
        gateway.connect('Pos-58'),
        throwsA(isA<PrinterException>()),
      );
      await expectLater(gateway.close(), throwsA(isA<PrinterException>()));
      expect(arguments.last['documentOpen'], false);
    },
  );
  test(
    'timeout drains pending write before abort and rejects simultaneous sends',
    () async {
      final pending = Completer<Object?>();
      final writing = Completer<void>();
      gateway = WindowsPrinterGateway(
        isWindows: true,
        operation: (name, args) async {
          if (name == 'write') {
            calls.add(name);
            writing.complete();
            return pending.future;
          }
          return operation(name, args);
        },
      );
      final service = TicketPrintService(
        gateway,
        writeTimeout: const Duration(milliseconds: 5),
      );
      final first = service.send(profile: windowsProfile(), bytes: [10]);
      await writing.future;
      expect((await first).failure, PrinterFailure.timeout);
      expect(service.isBusy, true);
      expect(
        (await service.send(profile: windowsProfile(), bytes: [10])).failure,
        PrinterFailure.busy,
      );
      pending.complete(null);
      await service.dispose();
      expect(calls.where((c) => c == 'write'), hasLength(1));
      expect(arguments.last['commit'], false);
    },
  );
}
