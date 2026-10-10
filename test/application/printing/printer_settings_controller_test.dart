import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_settings_controller.dart';
import 'package:pos_flutter/application/printing/printer_settings_exception.dart';

import '../../support/fake_printer_settings_store.dart';

void main() {
  late FakePrinterSettingsStore store;
  late PrinterSettingsController controller;
  PrinterProfile profile(String address, [String alias = 'Same name']) =>
      PrinterProfile(
        address: address,
        alias: alias,
        paper: PrinterPaper.mm58,
        printableWidthDots: 384,
        imageCommand: PrinterImageCommand.gsV0,
      );
  final a = profile('AA:BB:CC:DD:EE:01');
  final b = profile('AA:BB:CC:DD:EE:02');
  setUp(() async {
    store = FakePrinterSettingsStore();
    controller = PrinterSettingsController(store);
    await controller.load();
  });
  tearDown(() async => controller.dispose());

  test(
    'serial mutations use latest committed state and identity is address',
    () async {
      await Future.wait([controller.upsert(a), controller.upsert(b)]);
      await controller.upsert(profile(' aa:bb:cc:dd:ee:01 ', 'Edited'));
      expect(controller.settings.printers, hasLength(2));
      expect(controller.settings.printers.first.alias, 'Edited');
      expect(controller.settings.printers.last.alias, 'Same name');
      await controller.setDefault(a.address.toLowerCase());
      expect(controller.settings.defaultAddress, a.address);
      await expectLater(
        controller.setDefault('AA:BB:CC:DD:EE:FF'),
        throwsArgumentError,
      );
      expect(store.writes, 4);
      await controller.remove(a.address);
      expect(controller.settings.defaultAddress, isNull);
      expect(controller.settings.printers.single, same(b));
    },
  );

  test(
    'only publish a write after it succeeds; failure retains snapshot',
    () async {
      final changes = <Object>[];
      final subscription = controller.changes.listen(changes.add);
      store.pendingWrite = Completer<void>();
      final saving = controller.upsert(a);
      await Future<void>.delayed(Duration.zero);
      expect(controller.settings.printers, isEmpty);
      expect(changes, isEmpty);
      store.pendingWrite!.complete();
      await saving;
      await Future<void>.delayed(Duration.zero);
      expect(changes, hasLength(1));
      final confirmed = controller.settings;
      store.failWrite = true;
      await expectLater(
        controller.upsert(b),
        throwsA(isA<PrinterSettingsException>()),
      );
      expect(controller.settings, same(confirmed));
      expect(changes, hasLength(1));
      store.failWrite = false;
      await controller.upsert(b);
      await subscription.cancel();
    },
  );

  test(
    'load error blocks edits; recovery is explicit and failure stays blocked',
    () async {
      await controller.upsert(a);
      final confirmed = controller.settings;
      store.readError = const PrinterSettingsException(
        PrinterSettingsFailure.corrupt,
      );
      await controller.load();
      expect(controller.settings, same(confirmed));
      expect(controller.canEdit, isFalse);
      expect(store.recoveries, 0);
      await expectLater(controller.upsert(b), throwsStateError);
      store.failWrite = true;
      await expectLater(
        controller.recover(),
        throwsA(isA<PrinterSettingsException>()),
      );
      expect(controller.settings, same(confirmed));
      expect(controller.canEdit, isFalse);
      store.failWrite = false;
      expect(await controller.recover(), contains('preserved'));
      expect(controller.canEdit, isTrue);
      expect(controller.settings.printers, isEmpty);
    },
  );

  test(
    'dispose drains accepted saves before rejecting new mutations',
    () async {
      store.pendingWrite = Completer<void>();
      final first = controller.upsert(a);
      final second = controller.upsert(b);
      final closing = controller.dispose();
      store.pendingWrite!.complete();
      await Future.wait([first, second, closing]);
      expect(store.settings.printers, hasLength(2));
      await expectLater(controller.upsert(a), throwsStateError);
    },
  );
}
