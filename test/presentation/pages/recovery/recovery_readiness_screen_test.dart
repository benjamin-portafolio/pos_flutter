import 'package:pos_flutter/application/config/app_config_store.dart';
import 'package:pos_flutter/presentation/pages/recovery/recovery_access_tile.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_destination_inspector.dart';
import 'package:pos_flutter/application/recovery/recovery_readiness_service.dart';
import 'package:pos_flutter/application/recovery/recovery_snapshot_source.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_detection_settings_store.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_store.dart';
import 'package:pos_flutter/application/sync/sync_network_gate.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_server_detection_config.dart';
import 'package:pos_flutter/application/sync/sync_socket_listener.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/onboarding/first_run_setup_screen.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/sync_settings_page.dart';
import 'package:pos_flutter/presentation/pages/recovery/recovery_readiness_screen.dart';

class _UnusedSource implements RecoverySnapshotSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unused');
}

class _Service extends RecoveryReadinessService {
  _Service()
    : super(
        source: _UnusedSource(),
        privateDirectory: () async => Directory.systemTemp,
        deviceId: 'fixture',
        appRevision: 'fixture',
      );
  @override
  Future<Map<String, Object?>?> attempt() async => null;
  @override
  Future<List<Map<String, Object?>>> history() async => [];
  @override
  Future<Map<String, Object?>?> prepared() async => null;
  int calls = 0;
  Completer<Map<String, Object?>>? pending;
  @override
  Future<Map<String, Object?>> diagnose(
    AppMode mode,
    RecoveryCancellation c,
  ) async {
    calls++;
    return pending?.future ??
        Future.value({
          'cut': {'cut_at': '2026-11-09T12:00:00.000Z'},
          'snapshot_path': '/fixture/source.sqlite',
          'diagnostic': {
            'admissible': false,
            'blocking_count': 1,
            'blockers': [
              {'code': 'pending'},
            ],
            'warnings': ['global_server_completeness_unknown'],
            'counts': {'suppliers': 1},
          },
        });
  }
}

class _Inspector implements RecoveryDestinationInspector {
  _Inspector({this.complete = false});
  final bool complete;
  int calls = 0;
  int cancellations = 0;
  @override
  void cancel() {
    cancellations++;
  }

  @override
  Future<Map<String, Object?>> inspect({
    required AppMode mode,
    required Uri destination,
    required String token,
  }) async {
    calls++;
    return {
      'eligible': true,
      'reasons': <Object?>[],
      'commercial_recovery_complete': complete,
      'server_instance_id': 'fixture-server',
      'generation_id': 'fixture-generation',
    };
  }
}

class _WorkflowService extends _Service {
  var status = 'pending';
  @override
  Future<Map<String, Object?>> authorizeDestination(
    Uri destination,
    Map<String, Object?> package,
    AppMode mode,
  ) async => {
    'status': status,
    'request_id': 'approved-by-operator',
    if (status == 'approved') ...{
      'token': 'internal-token',
      'eligible': true,
      'commercial_recovery_complete': true,
      'server_instance_id': 'fixture-server',
      'generation_id': 'generation-fixture',
      'reasons': [],
    },
  };
  int transfers = 0, publications = 0;
  Map<String, Object?>? saved;
  final package = <String, Object?>{
    'package_id': 'package-fixture',
    'manifest_digest': 'digest-fixture',
    'package_path': '/private/package',
    'snapshot_path': '/private/source.sqlite',
    'cut': {
      'cut_at': '2026-11-09T12:00:00Z',
      'source': {'device_id': 'package-origin-fixture'},
    },
    'diagnostic': {
      'admissible': true,
      'counts': {},
      'warnings': [],
      'blockers': [],
    },
  };
  @override
  Future<Map<String, Object?>?> prepared() async => package;
  @override
  Future<Map<String, Object?>?> attempt() async => saved;
  @override
  Future<Map<String, Object?>> beginTransfer(
    Map<String, Object?> package,
    Map<String, Object?> target,
    String destination,
    String token,
    AppMode mode,
  ) async => saved = {
    'state': 'prepared',
    'destination': destination,
    'generation_id': 'generation-fixture',
    'recovery_id': 'recovery-fixture',
  };
  @override
  Future<Map<String, Object?>> transfer(
    RecoveryCancellation cancellation, {
    bool publish = false,
    bool abort = false,
    void Function(Map<String, Object?>)? onProgress,
  }) async {
    transfers++;
    if (publish) publications++;
    saved = {
      ...saved!,
      'state': abort
          ? 'aborted'
          : publish
          ? 'completed'
          : 'ready_to_commit',
      'total_chunks': 4,
      'received_chunks': 4,
      'progress': publish
          ? {
              'receipt': {'dataset_id': 'dataset-fixture'},
            }
          : {
              'diagnostic': {
                'valid': true,
                'summary': {'sales': '5'},
              },
            },
    };
    onProgress?.call(saved!);
    return saved!;
  }
}

class _Monitor implements SyncAvailabilityMonitor {
  bool started = true;
  int starts = 0;
  int stops = 0;
  @override
  bool get isStarted => started;
  @override
  void start() {
    starts++;
    started = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    started = false;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('Unused');
}

class _Socket implements SyncSocketListener {
  @override
  void stop() {}
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('Unused');
}

class _EndpointStore implements SyncEndpointStore {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('No debe cambiar endpoint');
}

class _WaitingEndpointStore implements SyncEndpointStore {
  final saving = Completer<void>();
  @override
  Future<void> saveBaseUrl(String baseUrl) => saving.future;
  @override
  Future<String?> readBaseUrl() async => null;
}

class _FailingConfigStore implements AppConfigStore {
  @override
  Future<void> saveConfig(AppConfig config) async =>
      throw StateError('Fixture de fallo al guardar');
  @override
  Future<AppConfig> readConfig() async => AppConfig.initial;
}

class _DetectionStore implements SyncDetectionSettingsStore {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('No debe guardar configuración');
}

class _Orchestrator implements SyncOrchestrator {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('No debe sincronizar');
}

void main() {
  testWidgets(
    'prepared package transfers, resumes review and publishes only after explicit selection',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _WorkflowService(),
          inspector = _Inspector(complete: true);
      Widget screen() => MaterialApp(
        home: RecoveryReadinessScreen(
          mode: AppMode.serverSync,
          service: service,
          inspector: inspector,
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data ==
                  'ID del dispositivo de origen: package-origin-fixture',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'URL HTTPS del destino'),
        'https://destination.example',
      );
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('Comprobar destino'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aprobación pendiente'), findsOneWidget);
      expect(find.text('Transferir y validar paquete'), findsNothing);
      service.status = 'rejected';
      await tester.tap(find.text('Comprobar destino'));
      await tester.pumpAndSettle();
      expect(find.textContaining('rechazó esta solicitud'), findsOneWidget);
      service.status = 'approved';
      await tester.tap(find.text('Comprobar destino'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Transferir y validar paquete'));
      await tester.tap(find.text('Transferir y validar paquete'));
      await tester.pumpAndSettle();
      expect(service.transfers, 1);
      expect(service.publications, 0);
      expect(find.text('Lotes confirmados: 4 / 4'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      final publish = find.widgetWithText(
        FilledButton,
        'Publicar recuperación',
      );
      expect(tester.widget<FilledButton>(publish).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();
      expect(service.publications, 1);
      expect(find.text('Abortar antes de publicar'), findsNothing);
      expect(find.text('Vincular este origen y reabrir'), findsOneWidget);
    },
  );

  testWidgets(
    'guardar configuración en curso impide entrar a recuperación hasta terminar',
    (tester) async {
      await getIt.reset();
      final endpoint = SyncEndpointConfig(
        initialBaseUrl: 'https://original.test',
      );
      final store = _WaitingEndpointStore();
      getIt.registerSingleton<SyncEndpointConfig>(endpoint);
      getIt.registerSingleton<SyncEndpointStore>(store);
      getIt.registerSingleton<AppConfigStore>(_FailingConfigStore());
      await tester.pumpWidget(const MaterialApp(home: FirstRunSetupScreen()));
      await tester.tap(find.byType(DropdownButtonFormField<AppMode>));
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
      expect(store.saving.isCompleted, false);
      await tester.scrollUntilVisible(
        find.byType(RecoveryAccessTile),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      final tile = find.descendant(
        of: find.byType(RecoveryAccessTile),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(tile).onTap, isNull);
      store.saving.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<ListTile>(tile).onTap, isNotNull);
      expect(find.byType(RecoveryReadinessScreen), findsNothing);
      expect(endpoint.baseUrl, 'https://original.test');
      await tester.pumpWidget(const SizedBox());
      await getIt.reset();
    },
  );

  testWidgets(
    'un diagnóstico bloqueado conserva sus razones y no abre una conexión',
    (tester) async {
      final service = _Service();
      final inspector = _Inspector();
      await tester.pumpWidget(
        MaterialApp(
          home: RecoveryReadinessScreen(
            mode: AppMode.serverSync,
            service: service,
            inspector: inspector,
          ),
        ),
      );
      await tester.tap(find.text('Diagnosticar origen'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-11-09'), findsOneWidget);
      expect(find.textContaining('eventos pendientes'), findsOneWidget);
      expect(find.textContaining('cotizaciones'), findsOneWidget);
      expect(find.text('Comprobar destino'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(inspector.calls, 0);
    },
  );
  testWidgets(
    'doble pulsación y salida durante diagnóstico no duplican ni usan widget eliminado',
    (tester) async {
      final service = _Service()..pending = Completer<Map<String, Object?>>();
      final inspector = _Inspector();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecoveryReadinessScreen(
                      mode: AppMode.standalone,
                      service: service,
                      inspector: inspector,
                    ),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnosticar origen'));
      await tester.tap(find.text('Diagnosticar origen'));
      await tester.pump();
      expect(service.calls, 1);
      expect(find.text('Comprobar destino'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      service.pending!.complete({});
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(inspector.cancellations, 1);
      expect(inspector.calls, 0);
    },
  );
  for (final mode in AppMode.values) {
    for (final initial in [true, false]) {
      testWidgets(
        'acceso real $mode ${initial ? 'inicial' : 'configurado'} preserva modo/setup/endpoint y pausa hasta volver',
        (tester) async {
          await getIt.reset();
          final config = AppConfigController(
            AppConfig.initial.copyWith(mode: mode, setupCompleted: !initial),
          );
          final saved = config.config;
          final endpoint = SyncEndpointConfig(
            initialBaseUrl: 'https://original.test',
          );
          final monitor = _Monitor()
            ..started = !initial && mode == AppMode.serverSync;
          final gate = SyncNetworkGate(
            isServerSync: () => config.config.isServerSync,
          );
          getIt.registerSingleton<AppConfigController>(config);
          getIt.registerSingleton<SyncEndpointConfig>(endpoint);
          getIt.registerSingleton<SyncNetworkGate>(gate);
          getIt.registerSingleton<SyncAvailabilityMonitor>(monitor);
          getIt.registerSingleton<SyncSocketListener>(_Socket());
          getIt.registerSingleton<RecoveryReadinessService>(_Service());
          getIt.registerSingleton<RecoveryDestinationInspector>(_Inspector());
          getIt.registerSingleton<SyncEndpointStore>(_EndpointStore());
          getIt.registerSingleton<SyncDetectionSettingsStore>(
            _DetectionStore(),
          );
          getIt.registerSingleton<SyncServerDetectionConfig>(
            SyncServerDetectionConfig(requireWifiForServerDetection: false),
          );
          getIt.registerSingleton<SyncOrchestrator>(_Orchestrator());
          await tester.pumpWidget(
            MaterialApp(
              home: initial
                  ? const FirstRunSetupScreen()
                  : const SyncSettingsPage(),
            ),
          );
          await tester.tap(
            find.text('Recuperar servidor desde este dispositivo'),
          );
          await tester.pumpAndSettle();
          expect(find.byType(RecoveryReadinessScreen), findsOneWidget);
          expect(gate.allowsNetwork, false);
          expect(monitor.started, false);
          expect(config.config, same(saved));
          expect(endpoint.baseUrl, 'https://original.test');
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(gate.allowsNetwork, mode == AppMode.serverSync);
          expect(
            monitor.starts,
            !initial && mode == AppMode.serverSync ? 1 : 0,
          );
          expect(config.config, same(saved));
          expect(endpoint.baseUrl, 'https://original.test');
          await tester.pumpWidget(const SizedBox());
          await config.dispose();
          await getIt.reset();
        },
      );
    }
  }
}
