import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Permite terminar el rasterizado nativo fuera del reloj simulado del widget.
Future<void> pumpReceiptImage(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    if (find.byType(Image).evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('La imagen del recibo no terminó de generarse.');
}
