import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'models/customer_statement_display.dart';

/// Dibuja el comprobante completo en PNG con formato vertical legible en
/// celular: títulos por sección, importes a la derecha con separador de miles
/// y saldo pendiente destacado. La misma imagen se muestra en la vista previa
/// y se comparte.
class CustomerStatementImageGenerator {
  static const double width = 460;
  static const double _pixelRatio = 2;
  static const double _margin = 20;
  static const double _contentWidth = width - _margin * 2;
  static const _ink = Color(0xFF222222);
  static const _muted = Color(0xFF6E6E6E);
  static const _line = Color(0xFFD6D6D6);
  static const _strong = Color(0xFF3A3A3A);
  static const _headerBg = Color(0xFFF0F0F0);
  static const _blockBg = Color(0xFFF2F4F3);
  static const _green = Color(0xFF1B7A3D);

  Future<Uint8List> generate(CustomerStatement statement) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(_pixelRatio);
    canvas.drawPaint(Paint()..color = const Color(0xFFFFFFFF));
    var y = 28.0;

    void text(
      String value, {
      bool bold = false,
      double size = 15,
      Color color = _ink,
      TextAlign align = TextAlign.left,
    }) {
      final painter = _text(
        value,
        _contentWidth,
        bold: bold,
        size: size,
        color: color,
        align: align,
      );
      painter.paint(canvas, Offset(_margin, y));
      y += painter.height + 8;
      painter.dispose();
    }

    void rule({bool strong = false}) {
      canvas.drawLine(
        Offset(_margin, y),
        Offset(_margin + _contentWidth, y),
        Paint()
          ..color = strong ? _strong : _line
          ..strokeWidth = strong ? 2 : 1,
      );
      y += 18;
    }

    void row(
      List<String> cells,
      List<double> fractions, {
      bool header = false,
      bool bold = false,
      Color? color,
    }) {
      final painters = <TextPainter>[];
      for (var i = 0; i < cells.length; i++) {
        painters.add(
          _text(
            cells[i],
            _contentWidth * fractions[i] - 10,
            bold: bold || header,
            size: header ? 13 : 15,
            color: color ?? (header ? _muted : _ink),
            align: i == cells.length - 1 ? TextAlign.right : TextAlign.left,
          ),
        );
      }
      final height = painters.map((p) => p.height).reduce(math.max) + 16;
      if (header) {
        canvas.drawRect(
          Rect.fromLTWH(_margin, y, _contentWidth, height),
          Paint()..color = _headerBg,
        );
      }
      var x = _margin;
      for (var i = 0; i < painters.length; i++) {
        painters[i].paint(canvas, Offset(x + 6, y + 8));
        x += _contentWidth * fractions[i];
        painters[i].dispose();
      }
      y += height;
    }

    void receiptBlock(StatementReceipt receipt, {bool liquidado = false}) {
      text('Folio: ${receipt.folio}', size: 13);
      text('Fecha: ${receipt.date}', size: 13);
      if (receipt.itemRows.isEmpty) {
        text('Productos no disponibles', size: 13, color: _muted);
      } else {
        const columns = [0.40, 0.22, 0.15, 0.23];
        row(['Producto', 'Precio', 'Cant.', 'Total'], columns, header: true);
        for (final line in receipt.itemRows) {
          row(line, columns);
        }
      }
      row(
        ['Total de la compra', CustomerStatement.money(receipt.totalMinor)],
        [0.62, 0.38],
        bold: true,
      );
      if (liquidado) {
        text('Liquidado', bold: true, size: 13, color: _green);
      }
      y += 10;
    }

    void saldoBlock(CustomerStatement statement) {
      final lines = <(String, String, bool)>[
        (
          'Total de compras a crédito',
          CustomerStatement.money(statement.totalComprasMinor),
          false,
        ),
        (
          '− Total abonado a estos recibos',
          CustomerStatement.money(statement.totalAbonadoMinor),
          false,
        ),
        (
          '= Saldo pendiente',
          statement.saldoPendienteMinor == 0
              ? 'Sin saldo pendiente'
              : CustomerStatement.money(statement.saldoPendienteMinor),
          true,
        ),
      ];
      final painters = <(TextPainter, TextPainter, double)>[];
      var contentHeight = 0.0;
      for (final (label, value, emphasized) in lines) {
        final labelPainter = _text(
          label,
          _contentWidth * 0.58,
          bold: emphasized,
          size: emphasized ? 17 : 15,
          color: emphasized ? _ink : _muted,
        );
        final valuePainter = _text(
          value,
          _contentWidth * 0.42 - 6,
          bold: emphasized,
          size: emphasized ? 17 : 15,
          color: emphasized ? _ink : _muted,
          align: TextAlign.right,
        );
        final lineHeight =
            math.max(labelPainter.height, valuePainter.height) + 11;
        contentHeight += lineHeight;
        painters.add((labelPainter, valuePainter, lineHeight));
      }
      final blockTop = y;
      final blockHeight = contentHeight + 18;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            _margin - 8,
            blockTop,
            _contentWidth + 16,
            blockHeight,
          ),
          const Radius.circular(10),
        ),
        Paint()..color = _blockBg,
      );
      var cursor = blockTop + 10;
      for (final (labelPainter, valuePainter, lineHeight) in painters) {
        labelPainter.paint(canvas, Offset(_margin, cursor));
        valuePainter.paint(canvas, Offset(_margin + _contentWidth * 0.58, cursor));
        cursor += lineHeight;
        labelPainter.dispose();
        valuePainter.dispose();
      }
      y = blockTop + blockHeight + 10;
      if (statement.saldoFavorMinor > BigInt.zero) {
        text(
          'Saldo a favor: ${CustomerStatement.money(statement.saldoFavorMinor.toInt())}',
          size: 12,
          color: _green,
        );
      }
    }

    // Encabezado.
    if (statement.businessName != null) {
      text(statement.businessName!, bold: true, size: 18);
    }
    text('ESTADO DE CUENTA', bold: true, size: 20);
    text('Cliente: ${statement.clienteNombre}', size: 15);
    text(
      'Emitido: ${CustomerStatement.date(statement.issuedAt)}',
      size: 13,
      color: _muted,
    );
    text('Moneda: MXN', size: 13, color: _muted);
    y += 8;
    rule(strong: true);

    // Recibos pendientes.
    text('Recibos pendientes', bold: true, size: 16);
    if (statement.pendingReceipts.isEmpty) {
      text('Sin recibos pendientes', size: 13, color: _muted);
    }
    for (final receipt in statement.pendingReceipts) {
      receiptBlock(receipt);
    }
    y += 4;
    rule(strong: true);

    // Total de compras a crédito.
    row(
      [
        'Total de compras a crédito',
        CustomerStatement.money(statement.totalComprasMinor),
      ],
      [0.62, 0.38],
      bold: true,
    );
    if (statement.isOperacionReciente) {
      text(
        'Incluye los recibos liquidados en este abono',
        size: 12,
        color: _muted,
      );
    }
    y += 4;
    rule(strong: true);

    // Historial de abonos.
    text('Abonos aplicados a estos recibos', bold: true, size: 16);
    if (statement.payments.isEmpty) {
      text('Sin abonos aplicados a estos recibos', size: 13, color: _muted);
    }
    for (final payment in statement.payments) {
      row(
        [payment.date, CustomerStatement.money(payment.appliedMinor)],
        [0.62, 0.38],
      );
    }
    row(
      [
        'Total abonado a estos recibos',
        CustomerStatement.money(statement.totalAbonadoMinor),
      ],
      [0.62, 0.38],
      bold: true,
    );
    y += 4;
    rule(strong: true);

    // Saldo pendiente destacado.
    saldoBlock(statement);
    y += 4;
    rule(strong: true);

    // Recibos liquidados en este abono.
    if (statement.liquidatedReceipts.isNotEmpty) {
      text('Recibos liquidados en este abono', bold: true, size: 16);
      for (final receipt in statement.liquidatedReceipts) {
        receiptBlock(receipt, liquidado: true);
      }
    }
    y += 8;

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        (width * _pixelRatio).ceil(),
        (y * _pixelRatio).ceil(),
      );
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw StateError('No se pudo generar el estado de cuenta.');
        }
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  TextPainter _text(
    String value,
    double width, {
    required bool bold,
    required double size,
    Color color = _ink,
    TextAlign align = TextAlign.left,
  }) => TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(
        fontFamily: 'Roboto',
        color: color,
        fontSize: size,
        height: 1.3,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout(minWidth: width, maxWidth: width);
}