import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/sync/sync_detection_settings_file_store.dart';

void main() {
  group('SyncDetectionSettingsFileStore', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'sync_detection_settings_test_',
      );
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('returns false when no preference has been saved', () async {
      final store = SyncDetectionSettingsFileStore(
        directoryProvider: () async => directory,
      );

      expect(await store.readRequireWifiForServerDetection(), isFalse);
    });

    test(
      'uses the configured initial value when no preference exists',
      () async {
        final store = SyncDetectionSettingsFileStore(
          directoryProvider: () async => directory,
          defaultRequireWifiForServerDetection: true,
        );

        expect(await store.readRequireWifiForServerDetection(), isTrue);
      },
    );

    test('persists and reads the wifi detection preference', () async {
      final store = SyncDetectionSettingsFileStore(
        directoryProvider: () async => directory,
        defaultRequireWifiForServerDetection: true,
      );

      await store.saveRequireWifiForServerDetection(false);

      expect(await store.readRequireWifiForServerDetection(), isFalse);
    });
  });
}
