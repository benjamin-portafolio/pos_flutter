import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'models/sale_draft_display.dart';
import 'models/sale_receipt_display.dart';

/// Dibuja el ticket completo en PNG, independientemente del área visible.
class SaleReceiptImageGenerator {
  static const double width = 440;
  static const double _pixelRatio = 2;
  static const double _margin = 20;
  static const double _contentWidth = width - _margin * 2;

  Future<Uint8List> generate(SaleReceiptDisplay receipt) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pixelRatio);
    canvas.drawPaint(Paint()..color = const Color(0xFFFFFFFF));
    double y = 28;

    void text(String value, {bool bold = false, double size = 15}) {
      final painter = _text(value, _contentWidth, bold: bold, size: size);
      painter.paint(canvas, Offset(_margin, y));
      y += painter.height + 8;
      painter.dispose();
    }

    void rule({bool strong = false}) {
      canvas.drawLine(
        Offset(_margin, y),
        Offset(width - _margin, y),
        Paint()
          ..color = Color(strong ? 0xFF414141 : 0xFFD2D2D2)
          ..strokeWidth = strong ? 2 : 1,
      );
      y += 16;
    }

    void row(
      List<String> cells,
      List<double> fractions, {
      bool header = false,
      bool bold = false,
    }) {
      final painters = <TextPainter>[];
      for (var i = 0; i < cells.length; i++) {
        painters.add(
          _text(
            cells[i],
            _contentWidth * fractions[i] - 12,
            bold: bold || header,
            size: header ? 14 : 15,
            align: i == cells.length - 1 ? TextAlign.right : TextAlign.left,
          ),
        );
      }
      final height = painters.map((p) => p.height).reduce(math.max) + 20;
      if (header) {
        canvas.drawRect(
          Rect.fromLTWH(_margin, y, _contentWidth, height),
          Paint()..color = const Color(0xFFF0F0F0),
        );
      }
      double x = _margin;
      for (var i = 0; i < painters.length; i++) {
        painters[i].paint(canvas, Offset(x + 6, y + 10));
        x += _contentWidth * fractions[i];
        painters[i].dispose();
      }
      y += height;
    }

    text('RECIBO DE VENTA', bold: true, size: 20);
    text('Recibo # ${receipt.sale.id}', size: 13);
    text('Fecha: ${receipt.date}', size: 13);
    text('Moneda: ${receipt.sale.currency}', size: 13);
    if (receipt.sale.paymentReference != null) {
      text('Referencia: ${receipt.sale.paymentReference}', size: 13);
    }
    if (receipt.sale.clienteNombre != null) {
      text('Cliente: ${receipt.sale.clienteNombre}', size: 13);
    }
    y += 12;
    const paymentWidths = [0.24, 0.10, 0.40, 0.26];
    row(['Modo de pago', '#I', '#U', 'Monto'], paymentWidths, header: true);
    row([
      receipt.paymentLabel,
      '${receipt.distinctItems}',
      receipt.quantities,
      SaleDraftDisplay.money(receipt.sale.totalMinor),
    ], paymentWidths);
    y += 20;
    const itemWidths = [0.39, 0.23, 0.16, 0.22];
    row(['Nombre', 'Precio', 'Cant.', 'Total'], itemWidths, header: true);
    for (final item in receipt.itemRows) {
      row(item, itemWidths);
    }
    y += 8;
    rule(strong: true);
    for (final total in receipt.totals) {
      row(
        [total.$1, total.$2],
        [0.60, 0.40],
        bold: total.$1 == 'Total general',
      );
      if (total.$1 == 'Total general') {
        y += 6;
        rule();
      }
    }
    y += 24;

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        (width * _pixelRatio).ceil(),
        (y * _pixelRatio).ceil(),
      );
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('No se pudo generar el recibo.');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  TextPainter _text(
    String text,
    double width, {
    required bool bold,
    required double size,
    TextAlign align = TextAlign.left,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Roboto',
        color: const Color(0xFF383838),
        fontSize: size,
        height: 1.3,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout(minWidth: width, maxWidth: width);
}
