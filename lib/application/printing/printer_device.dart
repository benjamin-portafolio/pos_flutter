import 'printer_profile.dart';

/// A paired device or installed queue is not proof of ESC/POS compatibility.
class PrinterDevice {
  const PrinterDevice({
    required this.address,
    required this.name,
    this.transport = PrinterTransport.androidBluetooth,
  });
  final String address;
  final PrinterTransport transport;
  final String? name;
  String get destinationKey => transport == PrinterTransport.windowsSpooler
      ? 'windows:$address'
      : address.trim().toUpperCase();
}
