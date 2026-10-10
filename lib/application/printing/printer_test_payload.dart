import '../tickets/ticket_document.dart';
import 'printer_profile.dart';

/// Calibration document uses the same bounded raster path as a real ticket.
class PrinterTestPayload {
  static TicketDocument create(PrinterProfile profile) => TicketDocument(
    title: 'PRUEBA DE IMPRESIÓN',
    identifier: profile.alias,
    date: 'Prueba manual',
    currency: 'MXN',
    details: [
      'Dirección: ${profile.address}',
      'Papel: ${profile.paper == PrinterPaper.mm58 ? 58 : 80} mm',
      'Ancho: ${profile.printableWidthDots} puntos',
      'Método: ${profile.imageCommand.name}',
      'Las líneas horizontales delimitan los márgenes del contenido.',
    ],
    itemRows: const [
      [
        'Café de especialidad de la sierra con nombre largo y piñón\n'
            'Tueste medio, selección de origen',
        r'$200.00 / 1 kg',
        '0.750 kg',
        r'$150.00',
      ],
    ],
    totals: const [('Total de prueba', r'$150.00')],
    footer:
        'Fin de prueba. ñ Ñ á é í ó ú ü € °\n'
        'Revisa márgenes y continuidad en papel. El envío no confirma impresión física.',
  );
}
