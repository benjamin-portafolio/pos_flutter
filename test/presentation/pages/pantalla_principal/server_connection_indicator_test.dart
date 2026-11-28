import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/config/app_config_controller.dart';
import 'package:pos_flutter/application/sync/models/sync_availability_snapshot.dart';
import 'package:pos_flutter/application/sync/models/sync_local_status.dart';
import 'package:pos_flutter/application/sync/models/sync_problem.dart';
import 'package:pos_flutter/application/sync/sync_activity.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_status_controller.dart';
import 'package:pos_flutter/application/sync/sync_status_store.dart';
import 'package:pos_flutter/core/di/injection.dart';
import 'package:pos_flutter/presentation/pages/pantalla_principal/server_connection_indicator.dart';

void main() {
  tearDown(() => getIt.reset());

  testWidgets('standalone muestra modo local sin resolver servicios de red', (
    tester,
  ) async {
    getIt.registerSingleton<AppConfigController>(
      AppConfigController(AppConfig.initial),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ServerConnectionIndicator())),
    );
    expect(find.text('Modo local'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalle reactivo permite comprobar y consultar incidencias', (
    tester,
  ) async {
    final store = _Store();
    final activity = SyncActivity();
    final monitor = _Monitor(activity);
    var now = DateTime.now();
    final controller = SyncStatusController(
      store: store,
      activity: activity,
      monitor: monitor,
      now: () => now,
    );
    addTearDown(store.values.close);
    addTearDown(activity.dispose);
    getIt.registerSingleton<AppConfigController>(
      AppConfigController(AppConfig.initial.copyWith(mode: AppMode.serverSync)),
    );
    getIt.registerSingleton<SyncStatusController>(
      controller,
      dispose: (c) => c.dispose(),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ServerConnectionIndicator())),
    );
    store.values.add(const SyncLocalStatus(pending: 0, problems: []));
    await tester.pumpAndSettle();
    expect(monitor.checks, 0);
    await tester.tap(find.text('Sincronización por comprobar'));
    await tester.pumpAndSettle();
    expect(find.text('Sincronización de este dispositivo'), findsOneWidget);
    await tester.tap(find.text('Comprobar ahora'));
    await tester.pumpAndSettle();
    expect(monitor.checks, 1);
    expect(find.text('Recepción de cambios: Al día'), findsOneWidget);
    now = activity.verifiedAt!.add(const Duration(minutes: 1, seconds: 10));
    await tester.pump(const Duration(minutes: 1, seconds: 10));
    expect(find.text('Recepción de cambios: Por comprobar'), findsOneWidget);
    expect(find.textContaining('Última comprobación exitosa:'), findsOneWidget);
    store.values.add(
      const SyncLocalStatus(
        pending: 2,
        problems: [
          SyncProblem(
            eventId: 'conflicto',
            eventType: 'producto_creado',
            reason: 'Código duplicado',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cambios por enviar: 2'), findsOneWidget);
    await tester.tap(find.text('Ver problemas'));
    await tester.pumpAndSettle();
    expect(find.text('Código duplicado'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await getIt.unregister<SyncStatusController>();
  });

  testWidgets(
    'indicador compacto cabe a 320 px y respeta permiso de navegación',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store();
      final activity = SyncActivity();
      final monitor = _Monitor(activity);
      final controller = SyncStatusController(
        store: store,
        activity: activity,
        monitor: monitor,
      );
      addTearDown(store.values.close);
      addTearDown(activity.dispose);
      getIt.registerSingleton<AppConfigController>(
        AppConfigController(
          AppConfig.initial.copyWith(mode: AppMode.serverSync),
        ),
      );
      getIt.registerSingleton<SyncStatusController>(
        controller,
        dispose: (c) => c.dispose(),
      );
      var allowed = false;
      var closed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('PASTOR'),
              leading: const Icon(Icons.menu),
              actions: [
                ServerConnectionIndicator(
                  compact: true,
                  onOpen: () async => allowed,
                  onClose: () => closed++,
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.person_add),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.swap_horiz),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(ServerConnectionIndicator));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      allowed = true;
      await tester.tap(find.byType(ServerConnectionIndicator));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await getIt.unregister<SyncStatusController>();
    },
  );
}

class _Store implements SyncStatusStore {
  final values = StreamController<SyncLocalStatus>.broadcast();
  @override
  Stream<SyncLocalStatus> watch() => values.stream;
}

class _Monitor implements SyncAvailabilityMonitor {
  _Monitor(this.activity);
  final SyncActivity activity;
  int checks = 0;
  @override
  SyncAvailabilitySnapshot get snapshot =>
      const SyncAvailabilitySnapshot(status: SyncAvailabilityStatus.available);
  @override
  Stream<SyncAvailabilitySnapshot> get snapshots => const Stream.empty();
  @override
  Future<void> checkNow() async {
    checks++;
    await activity.run(() async {}, verifies: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
