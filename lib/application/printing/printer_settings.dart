import 'printer_profile.dart';

/// Validated installation-local snapshot for multiple destinations.
class PrinterSettings {
  PrinterSettings({
    required Iterable<PrinterProfile> printers,
    String? defaultAddress,
  }) : printers = List.unmodifiable(printers),
       defaultAddress = _normalizeDefault(printers, defaultAddress) {
    final addresses = this.printers.map((p) => p.destinationKey).toSet();
    if (addresses.length != this.printers.length ||
        (this.defaultAddress != null &&
            !addresses.contains(this.defaultAddress))) {
      throw ArgumentError('Duplicate printer or absent default destination');
    }
  }

  final List<PrinterProfile> printers;

  /// Destination key; legacy Bluetooth keys remain normalized MAC addresses.
  final String? defaultAddress;
}

String? _normalizeDefault(Iterable<PrinterProfile> printers, String? value) {
  if (value == null) return null;
  for (final profile in printers) {
    if (profile.destinationKey == value) return value;
  }
  final name = value.trim();
  for (final profile in printers) {
    if (profile.destinationKey == name) return profile.destinationKey;
  }
  for (final profile in printers) {
    if (profile.transport == PrinterTransport.androidBluetooth &&
        profile.address == name.toUpperCase()) {
      return profile.address;
    }
  }
  return name;
}
