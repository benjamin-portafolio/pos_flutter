import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';

/// Imagen completa del estado de cuenta que se está revisando, lista para compartir.
class CustomerAccountReceiptImageGenerator {
  Future<Uint8List> generate(String text) async {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xff111111),
          fontSize: 16,
          height: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 400);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    canvas.drawPaint(Paint()..color = const Color(0xffffffff));
    painter.paint(canvas, const Offset(20, 20));
    final height = ((painter.height + 40) * 2).ceil();
    painter.dispose();
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(880, height);
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
}
