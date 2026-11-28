import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/presentation/pages/recovery/recovery_activation_screen.dart';

void main() {
  testWidgets('initial setup announces completion before entering', (
    tester,
  ) async {
    final pending = Completer<void>();
    var entered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RecoveryActivationScreen(
          initialSetup: true,
          activate: () => pending.future,
          onActivated: () => entered++,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Entrar'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(entered, 0);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Sincronización inicial completada. Ya puedes usar la app'),
      findsOneWidget,
    );
    await tester.tap(find.text('Entrar'));
    expect(entered, 1);
  });

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
