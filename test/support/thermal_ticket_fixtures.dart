import 'package:pos_flutter/application/printing/printer_profile.dart';
import 'package:pos_flutter/application/tickets/ticket_document.dart';

PrinterProfile thermalProfile({
  PrinterPaper paper = PrinterPaper.mm58,
  PrinterImageCommand command = PrinterImageCommand.gsV0,
  int? width,
  bool cut = false,
  String address = 'AA:BB:CC:DD:EE:01',
  String? alias,
}) => PrinterProfile(
  address: address,
  alias: alias ?? (paper == PrinterPaper.mm58 ? 'A58' : 'B80'),
  paper: paper,
  printableWidthDots: width ?? (paper == PrinterPaper.mm58 ? 384 : 576),
  imageCommand: command,
  supportsCut: cut,
);

TicketDocument thermalDocument({int lines = 3}) => TicketDocument(
  title: 'RECIBO DE VENTA',
  identifier: 'Recibo # térmico-123',
  date: '09/10/2026 12:34',
  currency: 'MXN',
  details: ['Cliente: María Muñoz', 'Referencia: SPEI-ñ-42'],
  summary: [
    'Transferencia',
    '$lines',
    '2 piezas, 0.750 kg, 0.250 L',
    r'$245.00',
  ],
  itemRows: [
    for (var i = 0; i < lines; i++)
      [
        '${i + 1}. Café de especialidad de la sierra con nombre largo y piñón\nTueste medio, selección de origen',
        i % 3 == 0
            ? r'$200.00 / 1 kg'
            : i % 3 == 1
            ? 'Precio no disponible'
            : r'$35.00',
        i % 3 == 0
            ? '0.750 kg'
            : i % 3 == 1
            ? '0.250 L'
            : '2',
        i % 3 == 1 ? 'Importe no disponible' : r'$150.00',
      ],
  ],
  totals: [
    ('Subtotal', r'$245.00'),
    ('Total general', r'$245.00'),
    ('Transferencia recibida', r'$245.00'),
  ],
  footer: 'Gracias, vuelva pronto. ñ Ñ á é í ó ú ü € °',
);
