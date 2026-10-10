enum PrinterTransport { androidBluetooth, windowsSpooler }

enum PrinterPaper { mm58, mm80 }

enum PrinterImageCommand { escStar, gsV0, gsL }

/// Installation-local compatibility settings. No connection or business state.
class PrinterProfile {
  PrinterProfile({
    required String address,
    this.transport = PrinterTransport.androidBluetooth,
    required String alias,
    required this.paper,
    required this.printableWidthDots,
    required this.imageCommand,
    this.supportsCut = false,
  }) : address = transport == PrinterTransport.androidBluetooth
           ? address.trim().toUpperCase()
           : address,
       alias = alias.trim() {
    if ((transport == PrinterTransport.androidBluetooth &&
            !RegExp(
              r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$',
            ).hasMatch(this.address)) ||
        this.address.trim().isEmpty ||
        this.address.contains('\u0000') ||
        this.alias.isEmpty ||
        this.alias.length > 80 ||
        printableWidthDots < 8 ||
        printableWidthDots > 2048 ||
        printableWidthDots % 8 != 0) {
      throw ArgumentError('Invalid printer profile');
    }
  }

  /// MAC for Bluetooth; exact installed queue name for Windows.
  final String address;
  final PrinterTransport transport;
  String get destinationKey => transport == PrinterTransport.windowsSpooler
      ? 'windows:$address'
      : address;

  final String alias;
  final PrinterPaper paper;
  final int printableWidthDots;
  final PrinterImageCommand imageCommand;
  final bool supportsCut;
}
