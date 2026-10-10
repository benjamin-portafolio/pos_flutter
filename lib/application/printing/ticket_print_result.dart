import 'printer_exception.dart';

class TicketPrintResult {
  const TicketPrintResult({this.failure, this.writeStarted = false});
  final PrinterFailure? failure;
  final bool writeStarted;
  bool get sent => failure == null;

  /// A failure after write starts may have left some or all bytes on paper.
  bool get mayHavePrinted => writeStarted;
}
