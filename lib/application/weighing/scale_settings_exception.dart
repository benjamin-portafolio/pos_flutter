enum ScaleSettingsFailure {
  corrupt,
  unsupportedVersion,
  readFailed,
  writeFailed,
}

class ScaleSettingsException implements Exception {
  const ScaleSettingsException(this.failure);

  final ScaleSettingsFailure failure;
  bool get canRecover =>
      failure == ScaleSettingsFailure.corrupt ||
      failure == ScaleSettingsFailure.unsupportedVersion;
}
