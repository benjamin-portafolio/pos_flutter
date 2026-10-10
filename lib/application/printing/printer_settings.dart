import 'printer_profile.dart';

/// Validated installation-local snapshot for multiple destinations.
class PrinterSettings {
  PrinterSettings({
    required Iterable<PrinterProfile> printers,
    String? defaultAddress,
  }) : printers = List.unmodifiable(printers),
       defaultAddress = defaultAddress?.trim().toUpperCase() {
    final addresses = this.printers.map((p) => p.address).toSet();
    if (addresses.length != this.printers.length ||
        (this.defaultAddress != null &&
            !addresses.contains(this.defaultAddress))) {
      throw ArgumentError('Duplicate printer or absent default destination');
    }
  }

  final List<PrinterProfile> printers;
  final String? defaultAddress;
}
