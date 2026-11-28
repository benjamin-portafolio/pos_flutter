import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/presentation/pages/recovery/server_administration_screen.dart';
import 'package:pos_flutter/presentation/pages/recovery/server_recovery_screen.dart';

void main() {
  testWidgets(
    'el panel ofrece recuperación sin abrir el formulario',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ServerAdministrationScreen(
            mode: AppMode.serverSync,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      expect(find.text('Panel de administración'), findsOneWidget);
      expect(find.text('Recuperación del servidor'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(ServerRecoveryScreen), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'el panel bloqueado no ofrece herramientas',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ServerAdministrationScreen(mode: AppMode.standalone),
        ),
      );
      expect(
        find.text('Disponible en computadora y en modo servidor.'),
        findsOneWidget,
      );
      expect(find.text('Entrar'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
