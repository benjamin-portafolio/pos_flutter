import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/recovery/recovery_activation_screen.dart';

void main() {
  testWidgets('failed first pull keeps operation blocked and permits retry', (
    tester,
  ) async {
    var calls = 0, activated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecoveryActivationScreen(
          activate: () async {
            calls++;
            if (calls == 1) throw StateError('offline');
          },
          onActivated: () => activated++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(activated, 0);
    expect(
      find.textContaining('Los datos y el progreso se conservan.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Reintentar descarga y activar'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(activated, 1);
  });
}
