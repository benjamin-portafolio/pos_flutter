import '../config/app_config.dart';

abstract interface class EmptyDeviceEnrollment {
  /// Returns true when the caller must reopen the runtime before operating.
  Future<bool> checkAndInstall(
    String endpoint, {
    required AppMode mode,
    AppConfig? setupConfig,
    required void Function() onDownloading,
  });
}
