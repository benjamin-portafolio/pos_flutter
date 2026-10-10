import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../application/printing/printer_profile.dart';
import '../../application/tickets/ticket_document.dart';
import 'thermal_ticket_band.dart';

/// Layout directly in printer dots. Only one band and one semantic row are
/// alive at a time; even a row taller than a band is painted across all bands.
class ThermalTicketRenderer {
  const ThermalTicketRenderer({this.bandHeight = 120})
    : assert(bandHeight > 0 && bandHeight <= 120 && bandHeight % 24 == 0);

  final int bandHeight;

  Stream<ThermalTicketBand> render(
    TicketDocument document,
    PrinterProfile profile,
  ) async* {
    final width = profile.printableWidthDots;
    ui.PictureRecorder? recorder;
    Canvas? canvas;
    var used = 0;
    void begin() {
      recorder = ui.PictureRecorder();
      canvas = Canvas(recorder!);
      canvas!.drawPaint(Paint()..color = const Color(0xFFFFFFFF));
      used = 0;
    }

    Future<ThermalTicketBand> finish() async {
      final picture = recorder!.endRecording();
      recorder = null;
      try {
        final image = await picture.toImage(width, used);
        try {
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (rgba == null) throw StateError('No se pudo rasterizar el ticket');
          final pixels = rgba.buffer.asUint8List(
            rgba.offsetInBytes,
            rgba.lengthInBytes,
          );
          final raster = Uint8List(width ~/ 8 * used);
          for (var y = 0; y < used; y++) {
            for (var x = 0; x < width; x++) {
              final offset = (y * width + x) * 4;
              // White backing, black glyphs; threshold includes antialiasing.
              if (pixels[offset] < 160) {
                raster[y * (width ~/ 8) + x ~/ 8] |= 0x80 >> (x % 8);
              }
            }
          }
          return ThermalTicketBand(width: width, height: used, raster: raster);
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
    }

    begin();
    try {
      for (final block in _blocks(document, profile)) {
        try {
          var consumed = 0;
          while (consumed < block.height) {
            final portion = math.min(
              bandHeight - used,
              block.height - consumed,
            );
            canvas!.save();
            canvas!.clipRect(
              Rect.fromLTWH(
                0,
                used.toDouble(),
                width.toDouble(),
                portion.toDouble(),
              ),
            );
            canvas!.translate(0, (used - consumed).toDouble());
            block.paint(canvas!);
            canvas!.restore();
            used += portion;
            consumed += portion;
            if (used == bandHeight) {
              yield await finish();
              begin();
            }
          }
        } finally {
          block.dispose();
        }
      }
      if (used > 0) yield await finish();
    } finally {
      // Cancellation may happen while a partially filled band is recorded.
      recorder?.endRecording().dispose();
    }
  }

  Iterable<_Block> _blocks(
    TicketDocument ticket,
    PrinterProfile profile,
  ) sync* {
    final width = profile.printableWidthDots.toDouble();
    final margin = math.min(8.0, width / 16);
    final content = width - margin * 2;
    _Block text(String value, {bool bold = false, double size = 24}) =>
        _Block.text([value], [content], margin, bold: bold, size: size);
    _Block row(
      List<String> cells,
      List<double> fractions, {
      bool bold = false,
    }) => _Block.text(
      cells,
      fractions.map((f) => content * f).toList(),
      margin,
      bold: bold,
    );
    yield _Block.space(12);
    yield text(ticket.title, bold: true, size: 28);
    yield text(ticket.identifier);
    yield text('${ticket.dateLabel}: ${ticket.date}');
    yield text('Moneda: ${ticket.currency}');
    for (final detail in ticket.details) {
      yield text(detail);
    }
    yield _Block.rule(margin, content);
    if (ticket.summary case final summary?) {
      const labels = [
        'Modo de pago',
        'Productos diferentes',
        'Cantidades',
        'Monto',
      ];
      for (var i = 0; i < summary.length; i++) {
        yield text('${labels[i]}: ${summary[i]}');
      }
      yield _Block.rule(margin, content);
    }
    final narrow = profile.paper == PrinterPaper.mm58 || content < 480;
    const columns = [0.35, 0.24, 0.19, 0.22];
    if (!narrow) {
      yield row(['Nombre', 'Precio', 'Cant.', 'Importe'], columns, bold: true);
    }
    for (final item in ticket.itemRows) {
      if (narrow) {
        yield text(item[0], bold: true);
        yield text('Cantidad: ${item[2]}');
        yield text(
          item[1] == 'Precio no disponible' ? item[1] : 'Precio: ${item[1]}',
        );
        yield text(
          item[3] == 'Importe no disponible' ? item[3] : 'Importe: ${item[3]}',
        );
      } else {
        yield row(item, columns);
      }
      yield _Block.rule(margin, content);
    }
    for (final total in ticket.totals) {
      // Unavailable values and large amounts retain their entire text.
      yield row([total.$1, total.$2], [0.56, 0.44], bold: true);
    }
    if (ticket.footer case final footer?) {
      yield _Block.rule(margin, content);
      yield text(footer);
    }
    yield _Block.space(12);
  }
}

class _Block {
  _Block(this.height, this.paint, this.dispose);

  factory _Block.space(int height) => _Block(height, (_) {}, () {});

  factory _Block.rule(double margin, double width) => _Block(
    12,
    (canvas) => canvas.drawRect(
      Rect.fromLTWH(margin, 5, width, 1),
      Paint()..color = const Color(0xFF000000),
    ),
    () {},
  );

  factory _Block.text(
    List<String> cells,
    List<double> widths,
    double margin, {
    bool bold = false,
    double size = 24,
  }) {
    final painters = <TextPainter>[];
    for (var i = 0; i < cells.length; i++) {
      final available = math.max(1.0, widths[i] - (cells.length > 1 ? 6 : 0));
      painters.add(
        TextPainter(
          text: TextSpan(
            text: cells[i],
            style: TextStyle(
              fontFamily: 'Roboto',
              color: const Color(0xFF000000),
              fontSize: size,
              height: 1.2,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: cells.length > 1 && i == cells.length - 1
              ? TextAlign.right
              : TextAlign.left,
        )..layout(minWidth: available, maxWidth: available),
      );
    }
    return _Block(
      painters.map((p) => p.height.ceil()).reduce(math.max) + 8,
      (canvas) {
        var x = margin;
        for (var i = 0; i < painters.length; i++) {
          painters[i].paint(canvas, Offset(x, 4));
          x += widths[i];
        }
      },
      () {
        for (final painter in painters) {
          painter.dispose();
        }
      },
    );
  }

  final int height;
  final void Function(Canvas) paint;
  final void Function() dispose;
}
