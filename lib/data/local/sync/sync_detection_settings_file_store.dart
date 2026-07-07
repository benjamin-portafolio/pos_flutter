import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../application/sync/sync_detection_settings_store.dart';

typedef SyncDetectionSettingsDirectoryProvider = Future<Directory> Function();

class SyncDetectionSettingsFileStore implements SyncDetectionSettingsStore {
  SyncDetectionSettingsFileStore({
    SyncDetectionSettingsDirectoryProvider? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'sync_require_wifi_detection.txt';

  final SyncDetectionSettingsDirectoryProvider _directoryProvider;

  @override
  Future<bool> readRequireWifiForServerDetection() async {
    final file = await _settingsFile();
    if (!await file.exists()) return false;

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
