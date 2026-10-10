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
/// A completed write means stream/queue acceptance, never physical printing.
abstract interface class PrinterGateway {
  Future<PrinterAvailability> availability();
  Future<PrinterPermission> permissionStatus();
  Future<PrinterPermission> requestPermission();

  /// Explicit discovery: paired Android devices or installed Windows queues.
  Future<List<PrinterDevice>> listDestinations();

  /// Opens a MAC destination or exact installed Windows printer name.
  Future<void> connect(String address);
  Future<void> write(List<int> bytes);

  /// Completes only when earlier native I/O has terminated and the transport handle is
  /// closed. Windows close aborts any unfinished job. Failure must not be interpreted as permission to send again.
  Future<void> close();
}

/// Queue transports must abort an incomplete document, rather than commit it.
abstract interface class PrinterJobGateway {
  Future<void> finishJob({required bool commit});
}
