import 'dart:typed_data';

import '../../application/printing/printer_profile.dart';
import '../../application/printing/ticket_encoder.dart';
import '../../application/tickets/ticket_document.dart';
import 'thermal_ticket_band.dart';
import 'thermal_ticket_renderer.dart';

/// ESC/POS image commands per Epson's reference. Firmware support is selected
/// by profile; no character table, drawer pulse, or transport logic is used.
class EscPosTicketEncoder implements TicketEncoder {
  const EscPosTicketEncoder({this.renderer = const ThermalTicketRenderer()});
  final ThermalTicketRenderer renderer;

  @override
  Stream<List<int>> encode(
    TicketDocument document,
    PrinterProfile profile,
  ) async* {
    var first = true;
    await for (final band in renderer.render(document, profile)) {
      final bytes = BytesBuilder(copy: false);
      if (first) {
        bytes.add([0x1b, 0x40, 0x1b, 0x61, 0]); // initialize, left align
        if (profile.imageCommand == PrinterImageCommand.escStar) {
          bytes.add([0x1d, 0x50, 0, 203, 0x1b, 0x33, 24]);
        }
        first = false;
      }
      bytes.add(encodeBand(band, profile.imageCommand));
      yield bytes.takeBytes();
    }
    if (first) throw StateError('Ticket vacío');
    yield [
      if (profile.imageCommand == PrinterImageCommand.escStar) ...[0x1b, 0x32],
      0x1b, 0x64, 3, // one final feed, after the complete ticket
      if (profile.supportsCut) ...[0x1d, 0x56, 0],
    ];
  }

  static Uint8List encodeBand(
    ThermalTicketBand band,
    PrinterImageCommand command,
  ) {
    final width = band.width;
    final height = band.height;
    final bytes = BytesBuilder(copy: false);
    switch (command) {
      case PrinterImageCommand.gsV0:
        final stride = width ~/ 8;
        bytes.add([
          0x1d,
          0x76,
          0x30,
          0,
          stride & 255,
          stride >> 8,
          height & 255,
          height >> 8,
        ]);
        bytes.add(band.raster);
      case PrinterImageCommand.gsL:
        final length = band.raster.length + 10;
        bytes.add([
          0x1d,
          0x28,
          0x4c,
          length & 255,
          length >> 8,
          48,
          112,
          48,
          1,
          1,
          49,
          width & 255,
          width >> 8,
          height & 255,
          height >> 8,
        ]);
        bytes.add(band.raster);
        bytes.add([0x1d, 0x28, 0x4c, 2, 0, 48, 50]);
      case PrinterImageCommand.escStar:
        for (var top = 0; top < height; top += 24) {
          bytes.add([0x1b, 0x2a, 33, width & 255, width >> 8]);
          final columns = Uint8List(width * 3);
          for (var x = 0; x < width; x++) {
            for (var dy = 0; dy < 24 && top + dy < height; dy++) {
              if ((band.raster[(top + dy) * (width ~/ 8) + x ~/ 8] &
                      (0x80 >> (x % 8))) !=
                  0) {
                columns[x * 3 + dy ~/ 8] |= 0x80 >> (dy % 8);
              }
            }
          }
          bytes.add(columns);
          bytes.addByte(10); // advances exactly these 24 image dots
        }
    }
    return bytes.takeBytes();
  }
}
