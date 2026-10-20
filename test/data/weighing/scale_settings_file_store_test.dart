import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/weighing/scale_profile.dart';
import 'package:pos_flutter/application/weighing/scale_session_service.dart';
import 'package:pos_flutter/application/weighing/scale_settings.dart';
import 'package:pos_flutter/application/weighing/scale_settings_controller.dart';
import 'package:pos_flutter/application/weighing/scale_settings_exception.dart';
import 'package:pos_flutter/data/local/weighing/scale_settings_file_store.dart';
import '../../support/fake_scale_gateway.dart';

void main() {
  late Directory directory;
  late ScaleSettingsFileStore store;
  late File file;
  final a = ScaleProfile(
    id: 'a',
    alias: 'Caja',
    port: 'COM8',
    systemId: 'PnP-A',
  );
  final b = ScaleProfile(
    id: 'b',
    alias: 'Caja',
    port: 'COM9',
    systemId: 'PnP-B',
  );
  Matcher failure(ScaleSettingsFailure type) =>
      isA<ScaleSettingsException>().having((e) => e.failure, 'failure', type);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('scale_settings_');
    store = ScaleSettingsFileStore(directoryProvider: () async => directory);
    file = File('${directory.path}/scale_settings.json');
  });
  tearDown(() async => directory.delete(recursive: true));

  test('absent settings read empty without creating any file', () async {
    expect((await store.readSettings()).profiles, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test(
    'B12 multiple profiles, explicit default, serial parameters survive reload',
    () async {
      final service = ScaleSessionService(FakeScaleGateway());
      final controller = ScaleSettingsController(
        store,
        sessionService: () => service,
      );
      await controller.load();
      await Future.wait([controller.upsert(a), controller.upsert(b)]);
      expect(controller.settings.defaultId, isNull);
      await controller.setDefault(b.id);
      final reloaded = await ScaleSettingsFileStore(
        directoryProvider: () async => directory,
      ).readSettings();
      expect(reloaded.profiles.map((p) => p.port), ['COM8', 'COM9']);
      expect(reloaded.profiles.map((p) => p.systemId), ['PnP-A', 'PnP-B']);
      expect(
        reloaded.profiles.every((p) => p.serial.isRhinoCompatible),
        isTrue,
      );
      expect(reloaded.defaultId, 'b');
      expect((jsonDecode(await file.readAsString()) as Map)['version'], 1);
      await controller.remove(b.id);
      expect((await store.readSettings()).defaultId, isNull);
      expect(await directory.list().length, 1);
      await controller.dispose();
      await service.dispose();
    },
  );

  for (final contents in [
    '{broken',
    '[]',
    '{"version":1,"profiles":[]}',
    '{"version":1,"profiles":[],"defaultId":"absent"}',
  ]) {
    test(
      'B14 damaged original requires explicit archived recovery: $contents',
      () async {
        await file.writeAsString(contents);
        await expectLater(
          store.readSettings(),
          throwsA(failure(ScaleSettingsFailure.corrupt)),
        );
        await expectLater(
          store.saveSettings(ScaleSettings(profiles: [a])),
          throwsA(failure(ScaleSettingsFailure.corrupt)),
        );
        expect(await file.readAsString(), contents);
        expect(
          await File(await store.recoverSettings()).readAsString(),
          contents,
        );
        expect((await store.readSettings()).profiles, isEmpty);
      },
    );
  }

  test(
    'B14 unknown version and invalid UTF8 preserved byte for byte',
    () async {
      final original = utf8.encode('{"version":99,"future":"data"}');
      await file.writeAsBytes(original);
      await expectLater(
        store.readSettings(),
        throwsA(failure(ScaleSettingsFailure.unsupportedVersion)),
      );
      await expectLater(
        store.saveSettings(ScaleSettings(profiles: [a])),
        throwsA(failure(ScaleSettingsFailure.unsupportedVersion)),
      );
      expect(await File(await store.recoverSettings()).readAsBytes(), original);
      await file.writeAsBytes([0xff, 0x00]);
      await expectLater(
        store.readSettings(),
        throwsA(failure(ScaleSettingsFailure.corrupt)),
      );
      expect(await File(await store.recoverSettings()).readAsBytes(), [
        0xff,
        0x00,
      ]);
    },
  );

  test(
    'B11 unknown model, duplicate id/destination, invalid serial rejected',
    () async {
      await store.saveSettings(ScaleSettings(profiles: [a, b]));
      final valid = await file.readAsString();
      for (final change in <void Function(Map<String, dynamic>)>[
        (json) => json['profiles'][0]['model'] = 'unknown',
        (json) => json['profiles'][0]['serial']['baudRate'] = 4800,
        (json) => json['profiles'][0]['alias'] = ' ',
        (json) => json['profiles'][1]['port'] = ' com8 ',
        (json) => json['profiles'][1]['id'] = 'a',
        (json) => json['profiles'][0]['systemId'] = '',
      ]) {
        final json = jsonDecode(valid) as Map<String, dynamic>;
        change(json);
        await file.writeAsString(jsonEncode(json));
        await expectLater(
          store.readSettings(),
          throwsA(failure(ScaleSettingsFailure.corrupt)),
        );
      }
    },
  );

  test(
    'B14 corruption after load blocks save without publishing or overwriting',
    () async {
      final service = ScaleSessionService(FakeScaleGateway());
      final controller = ScaleSettingsController(
        store,
        sessionService: () => service,
      );
      await controller.load();
      await controller.upsert(a);
      final confirmed = controller.settings;
      await file.writeAsString('{external damage');
      await expectLater(
        controller.upsert(b),
        throwsA(failure(ScaleSettingsFailure.corrupt)),
      );
      expect(controller.settings, same(confirmed));
      expect(controller.canEdit, isFalse);
      expect(await file.readAsString(), '{external damage');
      final archive = await controller.recover();
      expect(await File(archive).readAsString(), '{external damage');
      expect(controller.settings.profiles, isEmpty);
      await controller.dispose();
      await service.dispose();
    },
  );

  test(
    'B14 failed replacement retains original and cleans temporary file',
    () async {
      await store.saveSettings(ScaleSettings(profiles: [a]));
      final original = await file.readAsBytes();
      // Hold the confirmed file without delete sharing: Windows cannot replace it.
      final handle = await file.open(mode: FileMode.read);
      try {
        await expectLater(
          store.saveSettings(ScaleSettings(profiles: [a, b])),
          throwsA(failure(ScaleSettingsFailure.writeFailed)),
        );
        expect(await file.readAsBytes(), original);
        expect(await directory.list().length, 1);
      } finally {
        await handle.close();
      }
      await store.saveSettings(ScaleSettings(profiles: [a, b]));
      expect((await store.readSettings()).profiles, hasLength(2));
    },
    skip: !Platform.isWindows,
  );

  test(
    'B14 I/O read/write errors are distinct and never offer reset',
    () async {
      final failing = ScaleSettingsFileStore(
        directoryProvider: () async =>
            throw const FileSystemException('Unavailable'),
      );
      await expectLater(
        failing.readSettings(),
        throwsA(failure(ScaleSettingsFailure.readFailed)),
      );
      await expectLater(
        failing.saveSettings(ScaleSettings(profiles: [a])),
        throwsA(failure(ScaleSettingsFailure.writeFailed)),
      );
      expect(
        const ScaleSettingsException(
          ScaleSettingsFailure.readFailed,
        ).canRecover,
        isFalse,
      );
      await Directory(file.path).create();
      await expectLater(
        store.readSettings(),
        throwsA(failure(ScaleSettingsFailure.readFailed)),
      );
      await expectLater(
        store.recoverSettings(),
        throwsA(failure(ScaleSettingsFailure.writeFailed)),
      );
      expect(await Directory(file.path).exists(), isTrue);
    },
  );

  test(
    'B14 recovery failure keeps invalid original and controller confirmed state',
    () async {
      final service = ScaleSessionService(FakeScaleGateway());
      final controller = ScaleSettingsController(
        store,
        sessionService: () => service,
      );
      await controller.load();
      await controller.upsert(a);
      await file.writeAsString('{damaged');
      await controller.load();
      final confirmed = controller.settings;
      final handle = await file.open(mode: FileMode.read);
      try {
        await expectLater(
          controller.recover(),
          throwsA(failure(ScaleSettingsFailure.writeFailed)),
        );
        expect(await file.readAsString(), '{damaged');
        expect(controller.settings, same(confirmed));
        expect(controller.loadError!.canRecover, isTrue);
      } finally {
        await handle.close();
      }
      await controller.recover();
      expect(controller.settings.profiles, isEmpty);
      await controller.dispose();
      await service.dispose();
    },
    skip: !Platform.isWindows,
  );

  test(
    'direct operations serialize; stale tmp does not replace confirmed state',
    () async {
      await File('${file.path}.interrupted.tmp').writeAsString('{broken');
      await Future.wait([
        store.saveSettings(ScaleSettings(profiles: [a])),
        store.saveSettings(ScaleSettings(profiles: [a, b], defaultId: b.id)),
      ]);
      expect((await store.readSettings()).defaultId, b.id);
      expect((await store.readSettings()).profiles, hasLength(2));
    },
  );
}
