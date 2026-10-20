import 'scale_settings.dart';

abstract interface class ScaleSettingsStore {
  Future<ScaleSettings> readSettings();
  Future<void> saveSettings(ScaleSettings settings);

  /// Explicitly preserve the invalid original before committing empty settings.
  /// Returns the archive path only after replacement succeeds.
  Future<String> recoverSettings();
}
