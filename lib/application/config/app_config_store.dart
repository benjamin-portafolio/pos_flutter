import 'app_config.dart';

abstract interface class AppConfigStore {
  Future<AppConfig> readConfig();

  Future<void> saveConfig(AppConfig config);
}
