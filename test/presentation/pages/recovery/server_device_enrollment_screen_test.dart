import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_admin_client.dart';
import 'package:pos_flutter/presentation/pages/recovery/server_administration_screen.dart';
import 'package:pos_flutter/presentation/pages/recovery/server_device_enrollment_screen.dart';

class _Client implements RecoveryAdminClient {
  final actions = <String>[];
  bool enabled = false;
  bool published = true;
  bool fail = false;
  int reads = 0;
  @override
  Future<Map<String, Object?>> inspect({
    required AppMode mode,
    required String destination,
    required String credential,
  }) async {
    reads++;
    if (fail) throw const FormatException('Sin respuesta.');
    return {
      'server_instance_id': '11111111-1111-4111-8111-111111111111',
      'generation_id': '22222222-2222-4222-8222-222222222222',
      'revision': reads,
      'server_mode': published ? 'active' : 'empty',
      'dataset_id': published ? 'dataset' : null,
      'automatic_enrollment': enabled,
    };
  }

  @override
  Future<void> execute({
    required AppMode mode,
    required String destination,
    required String credential,
    required Map<String, Object?> snapshot,
    required String action,
    String? requestId,
  }) async {
    expect(credential, 'contraseña de prueba');
    expect(destination, 'https://pos.example');
    expect(requestId, isNull);
    actions.add(action);
    enabled = action == 'enrollment-enable';
  }

  @override
  void cancel() {}
}

void main() {
  testWidgets(
    'alta se administra separada, confirma cambios y descarta estado tras errores o edición',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();
      await tester.pumpWidget(
        MaterialApp(
          home: ServerAdministrationScreen(
            client: client,
            mode: AppMode.serverSync,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      await tester.tap(find.text('Alta de dispositivos'));
      await tester.pumpAndSettle();
      expect(find.byType(ServerDeviceEnrollmentScreen), findsOneWidget);
      expect(client.reads, 0);
      await tester.enterText(
        find.byKey(const ValueKey('server_admin_password')),
        'contraseña de prueba',
      );
      await tester.tap(find.text('Consultar estado'));
      await tester.pumpAndSettle();
      expect(find.text('Solicitudes de dispositivos'), findsNothing);
      expect(find.text('Alta deshabilitada'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(client.actions, isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(client.actions, isEmpty);
      for (final label in [
        'Habilitar alta de dispositivos',
        'Deshabilitar alta de dispositivos',
      ]) {
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, label));
        await tester.pumpAndSettle();
      }
      expect(client.actions, ['enrollment-enable', 'enrollment-disable']);
      client.fail = true;
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Habilitar alta de dispositivos'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin respuesta.'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      client.fail = false;
      await tester.tap(find.text('Consultar estado'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('server_admin_destination')),
        'https://other.example',
      );
      await tester.pump();
      expect(find.byType(SwitchListTile), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'no habilita antes de publicar',
    (tester) async {
      final client = _Client()..published = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ServerDeviceEnrollmentScreen(
            client: client,
            mode: AppMode.serverSync,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      await tester.tap(find.text('Consultar estado'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      expect(client.actions, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'standalone no abre canales administrativos',
    (tester) async {
      final client = _Client();
      await tester.pumpWidget(
        MaterialApp(
          home: ServerDeviceEnrollmentScreen(
            client: client,
            mode: AppMode.standalone,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      expect(client.reads, 0);
      expect(find.byType(TextField), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
