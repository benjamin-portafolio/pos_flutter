enum PrinterFailure {
  unsupportedPlatform,
  hardwareUnavailable,
  bluetoothOff,
  permissionDenied,
  permissionPermanentlyDenied,
  deviceNotBonded,
  connectionFailed,
  writeFailed,
  closeFailed,
  busy,
  timeout,
  disposed,
  transportError,
  generationFailed,
  canceled,
}

class PrinterException implements Exception {
  const PrinterException(this.failure);
  final PrinterFailure failure;
  @override
  String toString() => 'PrinterException(${failure.name})';
}
