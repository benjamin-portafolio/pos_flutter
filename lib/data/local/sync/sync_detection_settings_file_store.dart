import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../application/sync/sync_detection_settings_store.dart';

typedef SyncDetectionSettingsDirectoryProvider = Future<Directory> Function();

class SyncDetectionSettingsFileStore implements SyncDetectionSettingsStore {
  SyncDetectionSettingsFileStore({
    SyncDetectionSettingsDirectoryProvider? directoryProvider,
    this.defaultRequireWifiForServerDetection =
        _defaultRequireWifiForServerDetection,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'sync_require_wifi_detection.txt';
  static const _defaultRequireWifiForServerDetection = bool.fromEnvironment(
    'POS_INITIAL_REQUIRE_WIFI_FOR_SERVER_DETECTION',
    defaultValue: false,
  );

  final SyncDetectionSettingsDirectoryProvider _directoryProvider;
  final bool defaultRequireWifiForServerDetection;

  @override
  Future<bool> readRequireWifiForServerDetection() async {
    final file = await _settingsFile();
    if (!await file.exists()) return defaultRequireWifiForServerDetection;

    final value = (await file.readAsString()).trim().toLowerCase();
    return value == 'true' || value == '1' || value == 'yes';
  }

  @override
  Future<void> saveRequireWifiForServerDetection(bool enabled) async {
    final file = await _settingsFile();
    await file.writeAsString('$enabled\n', flush: true);
  }

  Future<File> _settingsFile() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    return File(p.join(directory.path, _fileName));
  }
}
