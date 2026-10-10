import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/printing/printer_settings.dart';
import 'package:pos_flutter/application/printing/printer_settings_controller.dart';
import 'package:pos_flutter/application/printing/printer_settings_exception.dart';
import 'package:pos_flutter/data/local/printing/printer_settings_file_store.dart';

void main() {
  late Directory directory;
  late PrinterSettingsFileStore store;
  late File file;
  final a = PrinterProfile(
    address: 'AA:BB:CC:DD:EE:01',
    alias: 'Same name',
    paper: PrinterPaper.mm58,
    printableWidthDots: 384,
    imageCommand: PrinterImageCommand.escStar,
  );
  final b = PrinterProfile(
    address: 'AA:BB:CC:DD:EE:02',
    alias: 'Same name',
    paper: PrinterPaper.mm80,
    printableWidthDots: 576,
    imageCommand: PrinterImageCommand.gsL,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('printer_settings_');
    store = PrinterSettingsFileStore(directoryProvider: () async => directory);
    file = File('${directory.path}/printer_settings.json');
  });
  tearDown(() async => directory.delete(recursive: true));
  Matcher failure(PrinterSettingsFailure type) =>
      isA<PrinterSettingsException>().having((e) => e.failure, 'failure', type);

  test('absent file is empty and reading does not create it', () async {
    expect((await store.readSettings()).printers, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test(
    'multiple independent profiles, duplicate-address edit, default and reload',
    () async {
      final controller = PrinterSettingsController(store);
      await controller.load();
      await Future.wait([controller.upsert(a), controller.upsert(b)]);
      await controller.setDefault(b.address);
      await controller.upsert(
        PrinterProfile(
          address: a.address.toLowerCase(),
          alias: 'Edited A',
          paper: a.paper,
          printableWidthDots: 360,
          imageCommand: a.imageCommand,
        ),
      );
      final reloaded = await PrinterSettingsFileStore(
        directoryProvider: () async => directory,
      ).readSettings();
      expect(reloaded.printers, hasLength(2));
      expect(reloaded.printers.first.printableWidthDots, 360);
      expect(reloaded.printers.last.paper, PrinterPaper.mm80);
      expect(reloaded.printers.last.imageCommand, PrinterImageCommand.gsL);
      expect(reloaded.defaultAddress, b.address);
      expect(reloaded.printers.every((p) => !p.supportsCut), isTrue);
      final json = jsonDecode(await file.readAsString()) as Map;
      expect(
        json.keys,
        unorderedEquals(['version', 'printers', 'defaultAddress']),
      );
      await controller.remove(b.address);
      expect((await store.readSettings()).defaultAddress, isNull);
      expect(await directory.list().length, 1); // no transient files remain
      await controller.dispose();
    },
  );

  test(
    'direct concurrent saves serialize; no stale temporary file is loaded',
    () async {
      await File('${file.path}.interrupted.tmp').writeAsString('{broken');
      await Future.wait([
        store.saveSettings(PrinterSettings(printers: [a])),
        store.saveSettings(
          PrinterSettings(printers: [a, b], defaultAddress: b.address),
        ),
      ]);
      expect((await store.readSettings()).defaultAddress, b.address);
      expect((await store.readSettings()).printers, hasLength(2));
    },
  );

  for (final contents in [
    '{broken',
    '[]',
    '{"version":1,"printers":[],"defaultAddress":"AA:BB:CC:DD:EE:01"}',
    '{"version":1,"printers":[]}',
  ]) {
    test(
      'invalid format is retained until explicit recovery: $contents',
      () async {
        await file.writeAsString(contents);
        await expectLater(
          store.readSettings(),
          throwsA(failure(PrinterSettingsFailure.corrupt)),
        );
        await expectLater(
          store.saveSettings(PrinterSettings(printers: [a])),
          throwsA(failure(PrinterSettingsFailure.corrupt)),
        );
        expect(await file.readAsString(), contents);
        final preserved = await store.recoverSettings();
        expect(await File(preserved).readAsString(), contents);
        expect((await store.readSettings()).printers, isEmpty);
      },
    );
  }

  test(
    'corruption discovered during save exposes recovery without publishing edits',
    () async {
      final controller = PrinterSettingsController(store);
      await controller.load();
      await controller.upsert(a);
      final confirmed = controller.settings;
      const corrupted = '{damaged after load';
      await file.writeAsString(corrupted);
      await expectLater(
        controller.upsert(b),
        throwsA(failure(PrinterSettingsFailure.corrupt)),
      );
      expect(controller.settings, same(confirmed));
      expect(controller.loadError!.canRecover, isTrue);
      expect(controller.canEdit, isFalse);
      expect(await file.readAsString(), corrupted);
      final archive = await controller.recover();
      expect(await File(archive).readAsString(), corrupted);
      expect(controller.canEdit, isTrue);
      expect(controller.settings.printers, isEmpty);
      await controller.dispose();
    },
  );

  test('unsupported version and non-UTF8 preserve original bytes', () async {
    const original = '{"version":99,"future":"data"}';
    await file.writeAsString(original);
    await expectLater(
      store.readSettings(),
      throwsA(failure(PrinterSettingsFailure.unsupportedVersion)),
    );
    expect(await File(await store.recoverSettings()).readAsString(), original);
    await file.writeAsBytes([0xff, 0x00]);
    await expectLater(
      store.readSettings(),
      throwsA(failure(PrinterSettingsFailure.corrupt)),
    );
    expect(await File(await store.recoverSettings()).readAsBytes(), [
      0xff,
      0x00,
    ]);
  });

  test(
    'duplicate addresses and unknown compatibility parameters reject entire file',
    () async {
      await store.saveSettings(PrinterSettings(printers: [a, b]));
      final valid =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final profiles = valid['printers'] as List;
      for (final change in <void Function()>[
        () => profiles[1]['address'] = a.address,
        () {
          profiles[1]['address'] = b.address;
          profiles[0]['paper'] = 'unknown';
        },
        () {
          profiles[0]['paper'] = 'mm58';
          profiles[0]['imageCommand'] = 'unknown';
        },
        () {
          profiles[0]['imageCommand'] = 'escStar';
          profiles[0]['printableWidthDots'] = 383;
        },
      ]) {
        change();
        await file.writeAsString(jsonEncode(valid));
        await expectLater(
          store.readSettings(),
          throwsA(failure(PrinterSettingsFailure.corrupt)),
        );
      }
    },
  );

  test(
    'filesystem write failure retains last confirmed state and usable queue',
    () async {
      var failDirectory = false;
      final blocker = File('${directory.path}/not_a_directory');
      await blocker.writeAsString('blocker');
      final failingStore = PrinterSettingsFileStore(
        directoryProvider: () async =>
            failDirectory ? Directory('${blocker.path}/child') : directory,
      );
      final controller = PrinterSettingsController(failingStore);
      await controller.load();
      await controller.upsert(a);
      final committed = await file.readAsBytes();
      final settings = controller.settings;
      failDirectory = true;
      await expectLater(
        controller.upsert(b),
        throwsA(failure(PrinterSettingsFailure.writeFailed)),
      );
      expect(controller.settings, same(settings));
      expect(await file.readAsBytes(), committed);
      failDirectory = false;
      await controller.upsert(b);
      expect((await failingStore.readSettings()).printers, hasLength(2));
      await controller.dispose();
    },
  );
}
