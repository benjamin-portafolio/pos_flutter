abstract interface class SyncDetectionSettingsStore {
  Future<bool> readRequireWifiForServerDetection();

  Future<void> saveRequireWifiForServerDetection(bool enabled);
}
