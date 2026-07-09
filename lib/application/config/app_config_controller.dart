import 'dart:async';

import 'app_config.dart';

class AppConfigController {
  AppConfigController(AppConfig initialConfig) : _config = initialConfig;

  AppConfig _config;
  final _changes = StreamController<AppConfig>.broadcast();

  AppConfig get config => _config;

  AppMode get mode => _config.mode;

  Stream<AppConfig> get changes => _changes.stream;

  void update(AppConfig config) {
    _config = config;
    if (!_changes.isClosed) {
      _changes.add(config);
    }
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}
