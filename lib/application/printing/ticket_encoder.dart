import '../tickets/ticket_document.dart';
import 'printer_profile.dart';

/// Lazy, bounded chunks in wire order, including one initialization and ending.
/// The consumer must await each write before requesting the next chunk and keep
/// one connection for the entire stream. Canceling releases renderer resources.
abstract interface class TicketEncoder {
  Stream<List<int>> encode(TicketDocument document, PrinterProfile profile);
}
