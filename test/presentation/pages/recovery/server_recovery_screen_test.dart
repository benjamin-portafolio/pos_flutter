import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_admin_client.dart';
import 'package:pos_flutter/presentation/pages/recovery/server_administration_access.dart';
import 'package:pos_flutter/presentation/pages/recovery/server_recovery_screen.dart';

class _Client implements RecoveryAdminClient {
  int reads = 0;
  String? lastCredential;
  final actions = <String>[];
  bool enabled = false;
  String? lastRequest;
  bool fail = false;
  @override
  Future<Map<String, Object?>> inspect({
    required AppMode mode,
    required String destination,
    required String credential,
  }) async {
    lastCredential = credential;
    reads++;
    if (fail) throw const FormatException('Sin respuesta. Consulta el estado.');
    return {
      'server_instance_id': '11111111-1111-4111-8111-111111111111',
      'generation_id': '22222222-2222-4222-8222-222222222222',
      'revision': reads,
      'server_mode': 'empty',
      'recovery_enabled': enabled,
      'active_recovery_id': null,
      'dataset_id': null,
      'eligibility': {'eligible': true, 'reasons': []},
      'requests': [
        {
          'request_id': '33333333-3333-4333-8333-333333333333',
          'package_id': 'paquete-A',
          'manifest_digest': 'huella-A',
          'source_device_id': 'tablet-A',
          'decision': 'pending',
          'created_at': '2026-11-27',
          'session_state': null,
          'received_chunks': 0,
        },
      ],
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
    lastRequest = requestId;
    actions.add(action);
    enabled = action == 'enable' || enabled;
  }

  @override
  void cancel() {}
}

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  test('access requires desktop and server_sync', () {
    for (final platform in [
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(canAdministerServer(AppMode.serverSync), true);
      expect(canAdministerServer(AppMode.standalone), false);
    }
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(canAdministerServer(AppMode.serverSync), false);
    }
  });
  testWidgets(
    'blocked screen performs no requests',
    (tester) async {
      final client = _Client();
      await tester.pumpWidget(
        MaterialApp(
          home: ServerRecoveryScreen(
            client: client,
            mode: AppMode.serverSync,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      expect(
        find.text('Disponible en computadora y en modo servidor.'),
        findsOneWidget,
      );
      expect(client.reads, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'el campo conserva foco y edición al mostrar la contraseña y después de un error',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client()..fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ServerRecoveryScreen(
            client: client,
            mode: AppMode.serverSync,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      final field = find.byKey(const ValueKey('server_admin_password'));
      await tester.tap(field);
      await tester.pump();
      final original = tester.widget<TextField>(field);
      expect(original.focusNode!.hasFocus, true);
      expect(tester.testTextInput.hasAnyClients, true);
      await tester.enterText(field, '  clave de prueba  ');
      await tester.tap(find.byTooltip('Mostrar contraseña'));
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, false);
      expect(
        tester.widget<TextField>(field).focusNode,
        same(original.focusNode),
      );
      expect(original.focusNode!.hasFocus, true);
      expect(original.controller!.text, '  clave de prueba  ');
      await tester.tap(find.byTooltip('Ocultar contraseña'));
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, true);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Sin respuesta. Consulta el estado.'), findsOneWidget);
      expect(tester.widget<TextField>(field).enabled, isNot(false));
      expect(tester.widget<TextField>(field).readOnly, false);
      await tester.tap(field);
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, true);
      await tester.enterText(field, 'otra contraseña editable');
      await tester.pump();
      expect(original.controller!.text, 'otra contraseña editable');
      expect(find.text('Sin respuesta. Consulta el estado.'), findsNothing);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'enables only after confirmation, refreshes and invalidates edited destination',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();
      await tester.pumpWidget(
        MaterialApp(
          home: ServerRecoveryScreen(
            client: client,
            mode: AppMode.serverSync,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      expect(client.reads, 0);
      await tester.enterText(
        find.byType(TextField).last,
        '  Mi contraseña de instalación 🔑  ',
      );
      await tester.tap(find.text('Consultar estado'));
      await tester.pumpAndSettle();
      expect(find.text('Habilitar recuperación'), findsOneWidget);
      await tester.tap(find.text('Habilitar recuperación'));
      await tester.pumpAndSettle();
      expect(client.actions, isEmpty);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(client.actions, isEmpty);
      await tester.tap(find.text('Habilitar recuperación'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Habilitar recuperación').last,
      );
      await tester.pumpAndSettle();
      expect(client.actions, ['enable']);
      expect(client.reads, 2);
      expect(client.lastCredential, '  Mi contraseña de instalación 🔑  ');
      expect(find.text('Deshabilitar recuperación'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'https://otro.example',
      );
      await tester.pump();
      expect(find.text('Deshabilitar recuperación'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  testWidgets(
    'aprueba la solicitud elegida después de revisar el origen',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client()..enabled = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ServerRecoveryScreen(
            client: client,
            mode: AppMode.serverSync,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      await tester.tap(find.text('Consultar estado'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Aprobar dispositivo'));
      await tester.tap(find.text('Aprobar dispositivo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Compara estos datos con los del dispositivo de origen.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Manifest SHA-256: huella-A'), findsWidgets);
      expect(client.actions, isEmpty);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Aprobar dispositivo').last,
      );
      await tester.pumpAndSettle();
      expect(client.actions, ['approve']);
      expect(client.lastRequest, '33333333-3333-4333-8333-333333333333');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'lost mutation response clears actionable state until a fresh query',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = _Client();
      await tester.pumpWidget(
        MaterialApp(
          home: ServerRecoveryScreen(
            client: client,
            mode: AppMode.serverSync,
            initialDestination: 'https://pos.example',
          ),
        ),
      );
      await tester.tap(find.text('Consultar estado'));
      await tester.pumpAndSettle();
      client.fail = true;
      await tester.tap(find.text('Habilitar recuperación'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Habilitar recuperación').last,
      );
      await tester.pumpAndSettle();
      expect(client.actions, ['enable']);
      expect(find.text('Habilitar recuperación'), findsNothing);
      expect(find.text('Sin respuesta. Consulta el estado.'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
