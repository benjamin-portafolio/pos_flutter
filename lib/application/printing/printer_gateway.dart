import 'printer_device.dart';

enum PrinterAvailability {
  unsupported,
  noHardware,
  permissionRequired,
  off,
  ready,
}

enum PrinterPermission { granted, denied, permanentlyDenied }

/// Only explicit callers may request permission or open a connection.
/// A completed write means bytes reached the stream, never a physical paper ACK.
abstract interface class PrinterGateway {
  Future<PrinterAvailability> availability();
  Future<PrinterPermission> permissionStatus();
  Future<PrinterPermission> requestPermission();
  Future<List<PrinterDevice>> bondedDevices();
  Future<void> connect(String address);
  Future<void> write(List<int> bytes);

  /// Completes only when earlier native I/O has terminated and the socket is
  /// closed. Failure must not be interpreted as permission to send again.
  Future<void> close();
}
