import 'printer_settings.dart';

/// Installation-local settings, independent of SQLite and business backups.
abstract interface class PrinterSettingsStore {
  Future<PrinterSettings> readSettings();
  Future<void> saveSettings(PrinterSettings settings);

  /// Explicit recovery of an unreadable format. Preserve the original first
  /// and return its archive path only after an empty configuration is committed.
  Future<String> recoverSettings();
}
