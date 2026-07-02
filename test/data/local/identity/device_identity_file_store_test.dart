import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pos_flutter/data/local/identity/device_identity_file_store.dart';

void main() {
  late Directory tempDir;
  var generatedIds = 0;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('device_identity_test_');
    generatedIds = 0;
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('getDeviceId genera y persiste un id local la primera vez', () async {
    final store = DeviceIdentityFileStore(
      directoryProvider: () async => tempDir,
      idGenerator: () {
        generatedIds++;
        return 'device_test_1';
      },
    );

    final deviceId = await store.getDeviceId();

    expect(deviceId, 'device_test_1');
    expect(generatedIds, 1);
    expect(
      await File(p.join(tempDir.path, 'device_identity.txt')).readAsString(),
      'device_test_1\n',
    );
  });

  test('getDeviceId reutiliza el id persistido', () async {
    final store = DeviceIdentityFileStore(
      directoryProvider: () async => tempDir,
      idGenerator: () {
        generatedIds++;
        return 'device_test_$generatedIds';
      },
    );

    final firstDeviceId = await store.getDeviceId();
    final secondDeviceId = await store.getDeviceId();

    expect(firstDeviceId, 'device_test_1');
    expect(secondDeviceId, 'device_test_1');
    expect(generatedIds, 1);
  });
}
