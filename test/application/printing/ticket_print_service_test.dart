import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_exception.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import '../../support/fake_printer_gateway.dart';
import '../../support/fake_ticket_encoder.dart';

PrinterProfile profile([String address = 'AA:BB:CC:DD:EE:01']) =>
    PrinterProfile(
      address: address,
      alias: 'Printer',
      paper: PrinterPaper.mm58,
      printableWidthDots: 384,
      imageCommand: PrinterImageCommand.gsV0,
    );
Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakePrinterGateway gateway;
  late TicketPrintService service;
  late FakeTicketEncoder encoder;
  setUp(() {
    gateway = FakePrinterGateway();
    encoder = FakeTicketEncoder()
      ..source = (() async* {
        yield [27, 64, 65, 10];
      });
    service = TicketPrintService(gateway, encoder: encoder);
  });

  test('construction does not request permission or connect', () {
    expect(gateway.calls, isEmpty);
    expect(service.isBusy, isFalse);
  });
  for (final pair in [
    (PrinterAvailability.unsupported, PrinterFailure.unsupportedPlatform),
    (PrinterAvailability.noHardware, PrinterFailure.hardwareUnavailable),
    (PrinterAvailability.off, PrinterFailure.bluetoothOff),
  ]) {
    test('handles ${pair.$1} without connecting', () async {
      gateway.state = pair.$1;
      expect((await service.printTest(profile())).failure, pair.$2);
      expect(gateway.calls.where((c) => c.startsWith('connect')), isEmpty);
      expect(gateway.writes, isEmpty);
    });
  }
  for (final permission in [
    PrinterPermission.denied,
    PrinterPermission.permanentlyDenied,
  ]) {
    test(
      'denied permission $permission prevents connection and writing',
      () async {
        gateway.permission = permission;
        gateway.requestedPermission = permission;
        final result = await service.printTest(profile());
        expect(
          result.failure,
          permission == PrinterPermission.denied
              ? PrinterFailure.permissionDenied
              : PrinterFailure.permissionPermanentlyDenied,
        );
        expect(gateway.calls.where((c) => c.startsWith('connect')), isEmpty);
        expect(
          gateway.calls.contains('requestPermission'),
          permission == PrinterPermission.denied,
        );
      },
    );
  }
  test('explicit request accepts permission and sends a test once', () async {
    gateway.permission = PrinterPermission.denied;
    final result = await service.printTest(profile());
    expect(result.sent, isTrue);
    expect(gateway.writes, hasLength(1));
    expect(gateway.calls.last, 'close');
    expect(service.isBusy, isFalse);
  });
  test('device absent never substitutes another paired destination', () async {
    expect(
      (await service.printTest(profile('AA:BB:CC:DD:EE:99'))).failure,
      PrinterFailure.deviceNotBonded,
    );
    expect(gateway.writes, isEmpty);
  });
  test('connection failure closes, does not retry or write', () async {
    gateway.connectFailure = PrinterFailure.connectionFailed;
    final result = await service.printTest(profile());
    expect(result.failure, PrinterFailure.connectionFailed);
    expect(result.mayHavePrinted, isFalse);
    expect(gateway.calls.last, 'close');
    expect(gateway.writes, isEmpty);
    expect(gateway.calls.where((c) => c.startsWith('connect')), hasLength(1));
  });
  for (final failure in [
    PrinterFailure.writeFailed,
    PrinterFailure.permissionDenied,
    PrinterFailure.timeout,
  ]) {
    test(
      'write error $failure is uncertain, closes and never retries',
      () async {
        gateway.writeFailure = failure;
        final result = await service.printTest(profile());
        expect(result.failure, failure);
        expect(result.mayHavePrinted, isTrue);
        expect(gateway.calls.last, 'close');
        expect(gateway.writes, hasLength(1));
      },
    );
  }
  test(
    'slow write rejects all concurrent sends and retains captured bytes',
    () async {
      gateway.pendingWrite = Completer<void>();
      final bytes = [27, 64, 65, 10];
      final first = service.send(profile: profile(), bytes: bytes);
      bytes[2] = 66;
      await flush();
      expect(service.isBusy, isTrue);
      final rejected = await Future.wait(
        List.generate(
          5,
          (_) => service.printTest(profile('AA:BB:CC:DD:EE:02')),
        ),
      );
      expect(rejected.every((r) => r.failure == PrinterFailure.busy), isTrue);
      expect(gateway.writes.single, [27, 64, 65, 10]);
      gateway.pendingWrite!.complete();
      expect((await first).sent, isTrue);
      expect(service.isBusy, isFalse);
      expect(gateway.writes, hasLength(1));
    },
  );
  test(
    'deadline reports early but native pending write AND close retain ownership',
    () async {
      service = TicketPrintService(
        gateway,
        encoder: encoder,
        writeTimeout: const Duration(milliseconds: 10),
      );
      gateway.pendingWrite = Completer<void>();
      gateway.pendingClose = Completer<void>();
      final result = await service.printTest(profile());
      expect(result.failure, PrinterFailure.timeout);
      expect(result.mayHavePrinted, isTrue);
      expect(service.isBusy, isTrue);
      expect((await service.printTest(profile())).failure, PrinterFailure.busy);
      expect(gateway.calls.contains('close'), isFalse);
      gateway.pendingWrite!.completeError(
        const PrinterException(PrinterFailure.writeFailed),
      );
      await flush();
      expect(gateway.calls.last, 'close');
      expect(service.isBusy, isTrue);
      gateway.pendingClose!.complete();
      await flush();
      expect(service.isBusy, isFalse);
      expect(gateway.writes, hasLength(1));
      gateway.pendingWrite = null;
      gateway.pendingClose = null;
      expect((await service.printTest(profile())).sent, isTrue);
    },
  );
  test(
    'late connection after timeout is closed without starting a write',
    () async {
      service = TicketPrintService(
        gateway,
        encoder: encoder,
        connectionTimeout: const Duration(milliseconds: 10),
      );
      gateway.pendingConnect = Completer<void>();
      expect(
        (await service.printTest(profile())).failure,
        PrinterFailure.timeout,
      );
      expect(service.isBusy, isTrue);
      gateway.pendingConnect!.complete();
      await flush();
      expect(gateway.writes, isEmpty);
      expect(gateway.calls.last, 'close');
      expect(service.isBusy, isFalse);
    },
  );
  test(
    'permission timeout drains late grant and never continues into connect',
    () async {
      gateway.permission = PrinterPermission.denied;
      gateway.pendingPermission = Completer<PrinterPermission>();
      service = TicketPrintService(
        gateway,
        encoder: encoder,
        permissionTimeout: const Duration(milliseconds: 10),
      );
      expect(
        (await service.printTest(profile())).failure,
        PrinterFailure.timeout,
      );
      expect(service.isBusy, isTrue);
      gateway.pendingPermission!.complete(PrinterPermission.granted);
      await flush();
      expect(gateway.writes, isEmpty);
      expect(service.isBusy, isFalse);
    },
  );
  test(
    'close timeout reports but unlocks only after successful late close',
    () async {
      gateway.pendingClose = Completer<void>();
      service = TicketPrintService(
        gateway,
        encoder: encoder,
        closeTimeout: const Duration(milliseconds: 10),
      );
      expect(
        (await service.printTest(profile())).failure,
        PrinterFailure.timeout,
      );
      expect(service.isBusy, isTrue);
      gateway.pendingClose!.complete();
      await flush();
      expect(service.isBusy, isFalse);
    },
  );
  test(
    'failed close quarantines sends until explicit dispose really closes',
    () async {
      gateway.closeFailure = PrinterFailure.closeFailed;
      expect(
        (await service.printTest(profile())).failure,
        PrinterFailure.closeFailed,
      );
      expect(service.isBusy, isTrue);
      expect((await service.printTest(profile())).failure, PrinterFailure.busy);
      await expectLater(service.dispose(), throwsA(isA<PrinterException>()));
      gateway.closeFailure = null;
      await service.dispose();
      expect(service.isBusy, isFalse);
      expect(
        (await service.printTest(profile())).failure,
        PrinterFailure.disposed,
      );
    },
  );
  test(
    'dispose waits write and close, rejects requests and never replays',
    () async {
      gateway.pendingWrite = Completer<void>();
      gateway.pendingClose = Completer<void>();
      final first = service.printTest(profile());
      await flush();
      var disposed = false;
      final disposing = service.dispose().then((_) => disposed = true);
      expect(
        (await service.printTest(profile())).failure,
        PrinterFailure.disposed,
      );
      gateway.pendingWrite!.complete();
      await flush();
      expect(disposed, isFalse);
      gateway.pendingClose!.complete();
      await first;
      await disposing;
      expect(gateway.writes, hasLength(1));
      expect(disposed, isTrue);
    },
  );
  test('dispose while connecting discards attempt before write', () async {
    gateway.pendingConnect = Completer<void>();
    final first = service.printTest(profile());
    await flush();
    final disposing = service.dispose();
    gateway.pendingConnect!.complete();
    expect((await first).failure, PrinterFailure.disposed);
    await disposing;
    expect(gateway.writes, isEmpty);
  });
  test(
    'A -> B -> A captures the destination and closes each attempt',
    () async {
      for (final address in [
        'AA:BB:CC:DD:EE:01',
        'AA:BB:CC:DD:EE:02',
        'AA:BB:CC:DD:EE:01',
      ]) {
        expect((await service.printTest(profile(address))).sent, isTrue);
      }
      expect(gateway.calls.where((c) => c.startsWith('connect')).toList(), [
        'connect:AA:BB:CC:DD:EE:01',
        'connect:AA:BB:CC:DD:EE:02',
        'connect:AA:BB:CC:DD:EE:01',
      ]);
      expect(gateway.calls.where((c) => c == 'close'), hasLength(3));
    },
  );
}
