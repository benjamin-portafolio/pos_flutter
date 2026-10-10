import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_exception.dart';
import 'package:pos_flutter/application/printing/printer_gateway.dart';
import 'package:pos_flutter/application/printing/ticket_print_service.dart';
import 'package:pos_flutter/application/tickets/ticket_document.dart';

import '../../support/fake_printer_gateway.dart';
import '../../support/fake_ticket_encoder.dart';
import '../../support/thermal_ticket_fixtures.dart';

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakePrinterGateway gateway;
  late FakeTicketEncoder encoder;
  late TicketPrintService service;
  setUp(() {
    gateway = FakePrinterGateway();
    encoder = FakeTicketEncoder();
    service = TicketPrintService(gateway, encoder: encoder);
  });
  tearDown(() => service.dispose());

  test(
    'configuration probe uses the captured raster profile and Spanish document',
    () async {
      final profile = thermalProfile(alias: 'Prueba de María Muñoz');
      expect((await service.printTest(profile)).sent, isTrue);
      expect(encoder.profiles.single, same(profile));
      final document = encoder.documents.single;
      expect(document.details.join('\n'), contains(profile.address));
      expect(document.details.join('\n'), contains('384'));
      expect(document.details.join('\n'), contains(profile.imageCommand.name));
      expect(document.itemRows.single.first, contains('piñón'));
      expect(document.itemRows.single[2], '0.750 kg');
      expect(document.footer, contains('ñ Ñ á é í ó ú ü'));
      expect(
        gateway.calls.where((c) => c.startsWith('connect:')),
        hasLength(1),
      );
      expect(gateway.calls.where((c) => c == 'close'), hasLength(1));
    },
  );

  test(
    'immutable document owns all nested rows, totals, details and summary',
    () {
      final rows = [
        ['ñ', 'price', 'qty', 'amount'],
      ];
      final totals = [('Total', 'no disponible')];
      final details = ['detail'];
      final summary = ['payment'];
      final doc = TicketDocument(
        title: 'title',
        identifier: 'id',
        date: 'date',
        currency: 'MXN',
        itemRows: rows,
        totals: totals,
        details: details,
        summary: summary,
      );
      rows[0][0] = 'changed';
      rows.clear();
      totals.clear();
      details.clear();
      summary.clear();
      expect(doc.itemRows.single.first, 'ñ');
      expect(doc.totals.single.$2, 'no disponible');
      expect(doc.details, ['detail']);
      expect(doc.summary, ['payment']);
      expect(() => doc.itemRows.single.add('x'), throwsUnsupportedError);
    },
  );
  test(
    'slow generation reserves global service, including configuration tests',
    () async {
      encoder.pending = Completer<void>();
      final document = thermalDocument();
      final profile = thermalProfile();
      final sending = service.printTicket(document: document, profile: profile);
      await _flush();
      expect(service.isBusy, isTrue);
      expect(gateway.writes, isEmpty);
      expect(gateway.calls.where((c) => c.startsWith('connect:')), isEmpty);
      expect(
        (await service.printTest(
          thermalProfile(address: 'AA:BB:CC:DD:EE:02'),
        )).failure,
        PrinterFailure.busy,
      );
      expect(
        (await service.printTicket(
          document: thermalDocument(),
          profile: profile,
        )).failure,
        PrinterFailure.busy,
      );
      encoder.pending!.complete();
      expect((await sending).sent, isTrue);
      expect(encoder.documents.single, same(document));
      expect(encoder.profiles.single, same(profile));
      expect(gateway.writes, [
        [27, 64, 1],
        [2],
        [27, 100, 3],
      ]);
      expect(gateway.calls.where((c) => c.startsWith('connect:')), [
        'connect:${profile.address}',
      ]);
      expect(gateway.calls.where((c) => c == 'close'), ['close']);
    },
  );
  test(
    'next band is not generated while native write/flush is pending',
    () async {
      var produced = 0;
      encoder.source = () async* {
        for (var i = 0; i < 8; i++) {
          produced++;
          yield [i];
        }
      };
      gateway.pendingWrite = Completer<void>();
      final sending = service.printTicket(
        document: thermalDocument(),
        profile: thermalProfile(),
      );
      await _flush();
      expect(produced, 1);
      expect(gateway.writes, [
        [0],
      ]);
      gateway.pendingWrite!.complete();
      expect((await sending).sent, isTrue);
      expect(produced, 8);
      expect(gateway.writes, List.generate(8, (i) => [i]));
      expect(
        gateway.calls.where((c) => c.startsWith('connect:')),
        hasLength(1),
      );
      expect(gateway.calls.where((c) => c == 'close'), hasLength(1));
    },
  );
  test(
    'generation timeout retains lock until original generation drains; no late write',
    () async {
      service = TicketPrintService(
        gateway,
        encoder: encoder,
        generationTimeout: const Duration(milliseconds: 10),
      );
      encoder.pending = Completer<void>();
      final result = await service.printTicket(
        document: thermalDocument(),
        profile: thermalProfile(),
      );
      expect(result.failure, PrinterFailure.timeout);
      expect(result.mayHavePrinted, isFalse);
      expect(service.isBusy, isTrue);
      expect(
        (await service.printTest(thermalProfile())).failure,
        PrinterFailure.busy,
      );
      encoder.pending!.complete();
      await _flush();
      expect(service.isBusy, isFalse);
      expect(gateway.writes, isEmpty);
      expect(gateway.calls.where((c) => c.startsWith('connect:')), isEmpty);
    },
  );
  test(
    'generation failures before write are distinct and release lock',
    () async {
      encoder.error = StateError('renderer failed');
      final result = await service.printTicket(
        document: thermalDocument(),
        profile: thermalProfile(),
      );
      expect(result.failure, PrinterFailure.generationFailed);
      expect(result.mayHavePrinted, isFalse);
      expect(gateway.writes, isEmpty);
      expect(service.isBusy, isFalse);
    },
  );
  test(
    'mid-ticket generation failure reports partial output and closes once',
    () async {
      encoder.source = () async* {
        yield [1];
        throw StateError('render');
      };
      final result = await service.printTicket(
        document: thermalDocument(),
        profile: thermalProfile(),
      );
      expect(result.failure, PrinterFailure.generationFailed);
      expect(result.mayHavePrinted, isTrue);
      expect(gateway.writes, [
        [1],
      ]);
      expect(gateway.calls.last, 'close');
    },
  );
  test(
    'closing intent during permission drops late callbacks before connect',
    () async {
      var active = true;
      gateway.permission = PrinterPermission.denied;
      gateway.pendingPermission = Completer<PrinterPermission>();
      final sending = service.printTicket(
        document: thermalDocument(),
        profile: thermalProfile(),
        isActive: () => active,
      );
      await _flush();
      expect(service.isBusy, isTrue);
      active = false;
      gateway.pendingPermission!.complete(PrinterPermission.granted);
      expect((await sending).failure, PrinterFailure.canceled);
      expect(encoder.documents, isEmpty);
      expect(gateway.writes, isEmpty);
    },
  );
  test(
    'route closes during first band generation: no connect; once writing, service owns rest',
    () async {
      var active = true;
      encoder.pending = Completer<void>();
      final sending = service.printTicket(
        document: thermalDocument(),
        profile: thermalProfile(),
        isActive: () => active,
      );
      await _flush();
      active = false;
      encoder.pending!.complete();
      expect((await sending).failure, PrinterFailure.canceled);
      expect(gateway.writes, isEmpty);
      active = true;
      encoder.pending = null;
      gateway.pendingWrite = Completer<void>();
      final second = service.printTicket(
        document: thermalDocument(),
        profile: thermalProfile(),
        isActive: () => active,
      );
      await _flush();
      active = false;
      gateway.pendingWrite!.complete();
      expect((await second).sent, isTrue);
      expect(gateway.writes, hasLength(3));
    },
  );
  test(
    'timeout in later band stops stream, drains write and close; no ending or retry',
    () async {
      final gate = Completer<void>();
      gateway.pendingWrite = gate;
      encoder.source = () async* {
        yield [1];
        gateway.pendingWrite = Completer<void>();
        yield [2];
        yield [3];
      };
      service = TicketPrintService(
        gateway,
        encoder: encoder,
        writeTimeout: const Duration(milliseconds: 30),
      );
      final sending = service.printTicket(
        document: thermalDocument(),
        profile: thermalProfile(),
      );
      await _flush();
      gate.complete();
      final result = await sending;
      expect(result.failure, PrinterFailure.timeout);
      expect(result.mayHavePrinted, isTrue);
      expect(gateway.writes, [
        [1],
        [2],
      ]);
      expect(service.isBusy, isTrue);
      gateway.pendingWrite!.complete();
      await _flush();
      expect(service.isBusy, isFalse);
      expect(gateway.writes, [
        [1],
        [2],
      ]);
      expect(gateway.calls.last, 'close');
    },
  );
}
