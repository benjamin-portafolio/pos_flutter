import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_exception.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';
import 'package:pos_flutter/data/printing/android_bluetooth_printer_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/pos/printer');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late AndroidBluetoothPrinterGateway gateway;
  setUp(() {
    gateway = AndroidBluetoothPrinterGateway(channel: channel, isAndroid: true);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });
  test('unsupported platforms make no plugin calls including close', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    gateway = AndroidBluetoothPrinterGateway(
      channel: channel,
      isAndroid: false,
    );
    expect(await gateway.availability(), PrinterAvailability.unsupported);
    await gateway.close();
    await expectLater(
      gateway.requestPermission(),
      throwsA(isA<PrinterException>()),
    );
    await expectLater(
      gateway.connect('AA:BB:CC:DD:EE:01'),
      throwsA(isA<PrinterException>()),
    );
    expect(calls, 0);
  });
  test('permission and availability states are typed', () async {
    for (final pair in [
      ('granted', PrinterPermission.granted),
      ('denied', PrinterPermission.denied),
      ('permanently_denied', PrinterPermission.permanentlyDenied),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => pair.$1);
      expect(await gateway.permissionStatus(), pair.$2);
      expect(await gateway.requestPermission(), pair.$2);
    }
    for (final pair in [
      ('ready', PrinterAvailability.ready),
      ('off', PrinterAvailability.off),
      ('permission_required', PrinterAvailability.permissionRequired),
      ('no_hardware', PrinterAvailability.noHardware),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => pair.$1);
      expect(await gateway.availability(), pair.$2);
    }
  });
  final errors = {
    'permission_denied': PrinterFailure.permissionDenied,
    'permission_permanently_denied': PrinterFailure.permissionPermanentlyDenied,
    'device_not_bonded': PrinterFailure.deviceNotBonded,
    'bluetooth_off': PrinterFailure.bluetoothOff,
    'no_hardware': PrinterFailure.hardwareUnavailable,
    'connection_failed': PrinterFailure.connectionFailed,
    'write_failed': PrinterFailure.writeFailed,
    'close_failed': PrinterFailure.closeFailed,
    'busy': PrinterFailure.busy,
    'timeout': PrinterFailure.timeout,
  };
  for (final entry in errors.entries) {
    test('native error ${entry.key} responds with typed error', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: entry.key),
      );
      await expectLater(
        gateway.write([65]),
        throwsA(
          isA<PrinterException>().having(
            (e) => e.failure,
            'failure',
            entry.value,
          ),
        ),
      );
    });
  }
  test(
    'paired names can repeat; address is passed separately without discovery',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'bondedDevices') {
          return [
            {'address': 'AA:BB:CC:DD:EE:01', 'name': 'Same'},
            {'address': 'AA:BB:CC:DD:EE:02', 'name': 'Same'},
          ];
        }
        if (call.method == 'connect') {
          expect(call.arguments, 'AA:BB:CC:DD:EE:02');
        }
        return null;
      });
      expect(
        (await gateway.listDestinations()).map((d) => d.address).toSet(),
        hasLength(2),
      );
      await gateway.connect('AA:BB:CC:DD:EE:02');
      expect(calls, ['bondedDevices', 'connect']);
    },
  );
  test(
    'write and close futures wait for native completion, with exact bytes',
    () async {
      final write = Completer<void>();
      final close = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'write') {
          expect(call.arguments, isA<Uint8List>());
          expect(call.arguments, [27, 64, 65, 10]);
          await write.future;
        } else if (call.method == 'close') {
          await close.future;
        }
        return null;
      });
      var written = false;
      var closed = false;
      final writing = gateway
          .write([27, 64, 65, 10])
          .then((_) => written = true);
      final closing = gateway.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(written, isFalse);
      expect(closed, isFalse);
      write.complete();
      await writing;
      expect(closed, isFalse);
      close.complete();
      await closing;
      expect(closed, isTrue);
    },
  );
}
