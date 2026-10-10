enum PrinterSettingsFailure {
  corrupt,
  unsupportedVersion,
  readFailed,
  writeFailed,
}

class PrinterSettingsException implements Exception {
  const PrinterSettingsException(this.failure);

  final PrinterSettingsFailure failure;
  bool get canRecover =>
      failure == PrinterSettingsFailure.corrupt ||
      failure == PrinterSettingsFailure.unsupportedVersion;
}
