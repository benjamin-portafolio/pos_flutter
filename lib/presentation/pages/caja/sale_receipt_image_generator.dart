import 'dart:typed_data';

import '../../tickets/ticket_image_generator.dart';
import 'models/sale_receipt_display.dart';

/// Adaptador del recibo vigente al dibujo compartido de tickets.
class SaleReceiptImageGenerator {
  static const double width = TicketImageGenerator.width;

  Future<Uint8List> generate(SaleReceiptDisplay receipt) =>
      TicketImageGenerator().generate(receipt.ticket);
}
