import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/application/sync/models/sync_pull_report.dart';
import 'package:pos_flutter/application/sync/sync_installation.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/main.dart';
import 'package:pos_flutter/application/recovery/empty_device_enrollment.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_store.dart';
import 'package:pos_flutter/presentation/app/app_restart_scope.dart';
import 'package:pos_flutter/presentation/onboarding/first_run_setup_screen.dart';

void main() {
  tearDown(() async => getIt.reset());

  testWidgets(
    'onboarding shows download, retries and saves pending before restart',
    (tester) async {
      final store = _ConfigStore(AppConfig.initial);
      final controller = AppConfigController(store.config);
      final enrollment = _Enrollment();
      getIt.registerSingleton<AppConfigStore>(store);
      getIt.registerSingleton<AppConfigController>(controller);
      getIt.registerSingleton<EmptyDeviceEnrollment>(enrollment);
      getIt.registerSingleton<SyncEndpointConfig>(
        SyncEndpointConfig(initialBaseUrl: 'http://localhost:3000'),
      );
      getIt.registerSingleton<SyncEndpointStore>(_EndpointStore());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        AppRestartScope(
          initialConfig: AppConfig.initial,
          restartDependencies: (_) async {
            expect(store.config.setupCompleted, isTrue);
            expect(store.config.initialSyncPending, isTrue);
            return DependencyBootstrap(appConfig: store.config);
          },
          builder: (config) => MaterialApp(
            home: config.setupCompleted
                ? const Scaffold(body: Text('Configuración guardada'))
                : const FirstRunSetupScreen(),
          ),
        ),
      );
      await tester.tap(find.text('Local'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Servidor').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Guardar y entrar'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Guardar y entrar'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('Descargando y verificando la base inicial…'),
        findsOneWidget,
      );
      expect(enrollment.setupConfig!.initialSyncPending, isTrue);
      enrollment.pending.completeError(StateError('Sin conexión'));
      await tester.pumpAndSettle();
      expect(store.config.setupCompleted, isFalse);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      enrollment.pending = Completer<bool>();
      await tester.scrollUntilVisible(
        find.text('Reintentar'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      enrollment.pending.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Configuración guardada'), findsOneWidget);
      expect(store.config.initialSyncPending, isTrue);
    },
  );

  testWidgets('initial download blocks home, retries and persists completion', (
    tester,
  ) async {
    final config = AppConfig.initial.copyWith(
      mode: AppMode.serverSync,
      setupCompleted: true,
      initialSyncPending: true,
    );
    final store = _ConfigStore(config);
    final controller = AppConfigController(config);
    final pull = _PullService();
    getIt.registerSingleton<AppConfigStore>(store);
    getIt.registerSingleton<AppConfigController>(controller);
    getIt.registerSingleton<SyncPullService>(pull);
    // Legacy servers have no enrollment binding.
    getIt.registerSingleton<SyncInstallation>(
      SyncInstallation(null, persist: (_) async {}),
    );
    addTearDown(controller.dispose);

    // No monitor is registered: pending setup must not start background sync.
    await startConfiguredRuntimeServices(config);
    await tester.pumpWidget(MainApp(initialConfig: config));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Preparando tus datos…'), findsOneWidget);
    expect(store.config.initialSyncPending, isTrue);
    expect(pull.calls, 1);

    pull.pending.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(store.config.initialSyncPending, isTrue);

    pull.pending = Completer<SyncPullReport>();
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(pull.calls, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Entrar'), findsNothing);

    pull.pending.complete(SyncPullReport.empty(lastCursor: 500));
    await tester.pumpAndSettle();
    expect(store.config.initialSyncPending, isFalse);
    expect(controller.config.initialSyncPending, isFalse);
    expect(
      find.text('Sincronización inicial completada. Ya puedes usar la app'),
      findsOneWidget,
    );
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

class _ConfigStore implements AppConfigStore {
  _ConfigStore(this.config);
  AppConfig config;
  @override
  Future<AppConfig> readConfig() async => config;
  @override
  Future<void> saveConfig(AppConfig config) async => this.config = config;
}

class _PullService implements SyncPullService {
  var pending = Completer<SyncPullReport>();
  var calls = 0;
  @override
  Future<SyncPullReport> pullAvailableEvents({int limit = 500}) {
    calls++;
    return pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _EndpointStore implements SyncEndpointStore {
  @override
  Future<String?> readBaseUrl() async => null;
  @override
  Future<void> saveBaseUrl(String baseUrl) async {}
}

class _Enrollment implements EmptyDeviceEnrollment {
  var pending = Completer<bool>();
  AppConfig? setupConfig;
  @override
  Future<bool> checkAndInstall(
    String endpoint, {
    required AppMode mode,
    AppConfig? setupConfig,
    required void Function() onDownloading,
  }) {
    this.setupConfig = setupConfig;
    onDownloading();
    return pending.future;
  }
}
