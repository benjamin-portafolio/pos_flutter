import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../application/config/app_config.dart';
import '../../../application/config/app_config_store.dart';

typedef AppConfigDirectoryProvider = Future<Directory> Function();

class AppConfigFileStore implements AppConfigStore {
  AppConfigFileStore({AppConfigDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const _fileName = 'app_config.json';

  final AppConfigDirectoryProvider _directoryProvider;

  @override
  Future<AppConfig> readConfig() async {
    final file = await _configFile();
    if (!await file.exists()) return AppConfig.initial;

    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        return AppConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return AppConfig.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      return AppConfig.initial;
    }

    return AppConfig.initial;
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    final file = await _configFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(config.toJson())}\n');
  }

  Future<File> _configFile() async {
    final directory = await _directoryProvider();
    await directory.create(recursive: true);
    return File(p.join(directory.path, _fileName));
  }
}
