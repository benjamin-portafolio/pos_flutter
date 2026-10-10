enum PrinterPaper { mm58, mm80 }

enum PrinterImageCommand { escStar, gsV0, gsL }

/// Installation-local compatibility settings. No connection or business state.
class PrinterProfile {
  PrinterProfile({
    required String address,
    required String alias,
    required this.paper,
    required this.printableWidthDots,
    required this.imageCommand,
    this.supportsCut = false,
  }) : address = address.trim().toUpperCase(),
       alias = alias.trim() {
    if (!RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$').hasMatch(this.address) ||
        this.alias.isEmpty ||
        this.alias.length > 80 ||
        printableWidthDots < 8 ||
        printableWidthDots > 2048 ||
        printableWidthDots % 8 != 0) {
      throw ArgumentError('Invalid Bluetooth printer profile');
    }
  }

  final String address;
  final String alias;
  final PrinterPaper paper;
  final int printableWidthDots;
  final PrinterImageCommand imageCommand;
  final bool supportsCut;
}
