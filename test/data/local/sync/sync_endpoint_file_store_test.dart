import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/sync/sync_endpoint_file_store.dart';

void main() {
  group('SyncEndpointFileStore', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sync_endpoint_test_');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('returns null when no endpoint has been saved', () async {
      final store = SyncEndpointFileStore(
        directoryProvider: () async {
          return directory;
        },
      );

      expect(await store.readBaseUrl(), isNull);
    });

    test('persists and reads the configured endpoint', () async {
      final store = SyncEndpointFileStore(
        directoryProvider: () async {
          return directory;
        },
      );

      await store.saveBaseUrl('http://192.168.1.20:3000');

      expect(await store.readBaseUrl(), 'http://192.168.1.20:3000');
    });
  });
}
