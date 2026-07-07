import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_detection_settings_store.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_store.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_server_detection_config.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/menu_lateral.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/sync_settings_page.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/sync_settings_screen.dart';

void main() {
  late _FakeSyncDetectionSettingsStore detectionSettingsStore;
  late SyncServerDetectionConfig serverDetectionConfig;

  setUp(() async {
    await getIt.reset();
    detectionSettingsStore = _FakeSyncDetectionSettingsStore();
    serverDetectionConfig = SyncServerDetectionConfig();

    getIt.registerSingleton<SyncEndpointConfig>(SyncEndpointConfig());
    getIt.registerSingleton<SyncEndpointStore>(_FakeSyncEndpointStore());
    getIt.registerSingleton<SyncDetectionSettingsStore>(detectionSettingsStore);
    getIt.registerSingleton<SyncServerDetectionConfig>(serverDetectionConfig);
    getIt.registerSingleton<SyncAvailabilityMonitor>(
      _FakeSyncAvailabilityMonitor(),
    );
    getIt.registerSingleton<SyncOrchestrator>(_FakeSyncOrchestrator());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('Chat de ayuda opens sync settings as a full page', (
    tester,
  ) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: const MenuLateral(),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Chat de ayuda'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat de ayuda'));
    await tester.pumpAndSettle();

    expect(find.byType(SyncSettingsPage), findsOneWidget);
    expect(find.byType(SyncSettingsScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Chat de ayuda'), findsOneWidget);
  });

  testWidgets('Sync settings persists wifi detection preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SyncSettingsScreen())),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(detectionSettingsStore.savedValues, [true]);
    expect(serverDetectionConfig.requireWifiForServerDetection, isTrue);
  });
}

class _FakeSyncEndpointStore implements SyncEndpointStore {
  @override
  Future<String?> readBaseUrl() async => null;

  @override
  Future<void> saveBaseUrl(String baseUrl) async {}
}

class _FakeSyncDetectionSettingsStore implements SyncDetectionSettingsStore {
  final savedValues = <bool>[];

  @override
  Future<bool> readRequireWifiForServerDetection() async => false;

  @override
  Future<void> saveRequireWifiForServerDetection(bool enabled) async {
    savedValues.add(enabled);
  }
}

class _FakeSyncAvailabilityMonitor implements SyncAvailabilityMonitor {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncOrchestrator implements SyncOrchestrator {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
