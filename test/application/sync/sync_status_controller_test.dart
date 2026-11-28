import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/models/sync_availability_snapshot.dart';
import 'package:pos_flutter/application/sync/models/sync_local_status.dart';
import 'package:pos_flutter/application/sync/models/sync_problem.dart';
import 'package:pos_flutter/application/sync/sync_activity.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_status_controller.dart';
import 'package:pos_flutter/application/sync/sync_status_store.dart';

void main() {
  late _Store store;
  late _Monitor monitor;
  late SyncActivity activity;
  late SyncStatusController controller;
  late DateTime now;

  setUp(() {
    store = _Store();
    monitor = _Monitor();
    activity = SyncActivity();
    now = DateTime.now();
    controller = SyncStatusController(
      store: store,
      activity: activity,
      monitor: monitor,
      now: () => now,
    );
    store.values.add(const SyncLocalStatus(pending: 0, problems: []));
  });

  tearDown(() async {
    controller.dispose();
    activity.dispose();
    await store.values.close();
    await monitor.values.close();
  });

  test('conexión y cola vacía no prueban sincronización', () {
    expect(controller.isCurrent, isFalse);
    expect(controller.label, 'Sincronización por comprobar');
  });

  test('verificación caduca y conserva fecha de última comprobación', () async {
    await activity.run(() async {}, verifies: true);
    now = activity.verifiedAt!.add(const Duration(seconds: 10));
    expect(controller.isCurrent, isTrue);
    expect(controller.label, contains('hace 10 s'));
    now = now.add(const Duration(minutes: 1));
    expect(controller.isCurrent, isFalse);
    expect(controller.verifiedAt, isNotNull);
  });

  test(
    'desconectar durante un pull impide que su respuesta restaure el verde',
    () async {
      final delayed = Completer<void>();
      final running = activity.run(() => delayed.future, verifies: true);
      monitor.emit(SyncAvailabilityStatus.unavailable);
      delayed.complete();
      await running;
      monitor.emit(SyncAvailabilityStatus.available);
      expect(controller.isCurrent, isFalse);
      await activity.run(() async {}, verifies: true);
      expect(controller.isCurrent, isTrue);
    },
  );

  test('nuevo pendiente invalida verde aun si luego desaparece', () async {
    await activity.run(() async {}, verifies: true);
    store.values.add(const SyncLocalStatus(pending: 1, problems: []));
    expect(controller.isCurrent, isFalse);
    expect(controller.label, '1 cambio por enviar');
    store.values.add(const SyncLocalStatus(pending: 0, problems: []));
    expect(controller.isCurrent, isFalse);
    await activity.run(() async {}, verifies: true);
    expect(controller.isCurrent, isTrue);
  });

  test('conflictos reportados y errores locales bloquean verde', () async {
    await activity.run(() async {}, verifies: true);
    store.values.add(
      const SyncLocalStatus(
        pending: 0,
        problems: [
          SyncProblem(
            eventId: 'e',
            eventType: 'producto_creado',
            reason: 'Conflicto',
          ),
        ],
      ),
    );
    expect(controller.isCurrent, isFalse);
    expect(controller.label, contains('requiere atención'));
    store.values.addError(StateError('lectura fallida'));
    expect(controller.isCurrent, isFalse);
    expect(controller.localError, contains('lectura fallida'));
  });

  test(
    'desconexión invalida verificación hasta una nueva comprobación',
    () async {
      await activity.run(() async {}, verifies: true);
      monitor.emit(SyncAvailabilityStatus.unavailable);
      expect(controller.isCurrent, isFalse);
      expect(controller.label, contains('Sin conexión'));
      monitor.emit(SyncAvailabilityStatus.available);
      expect(controller.isCurrent, isFalse);
      await controller.checkNow();
      expect(monitor.checks, 1);
    },
  );

  test(
    'operaciones concurrentes no ocultan errores ni muestran verde temprano',
    () async {
      final delayed = Completer<void>();
      final running = activity.run(() => delayed.future, verifies: true);
      expect(controller.busy, isTrue);
      await expectLater(
        activity.run(() async => throw StateError('falló')),
        throwsStateError,
      );
      delayed.complete();
      await running;
      expect(controller.busy, isFalse);
      expect(controller.isCurrent, isFalse);
      expect(controller.error, contains('falló'));
      await activity.run(() async {}, verifies: true);
      expect(controller.isCurrent, isTrue);
    },
  );
}

class _Store implements SyncStatusStore {
  final values = StreamController<SyncLocalStatus>.broadcast(sync: true);
  @override
  Stream<SyncLocalStatus> watch() => values.stream;
}

class _Monitor implements SyncAvailabilityMonitor {
  final values = StreamController<SyncAvailabilitySnapshot>.broadcast(
    sync: true,
  );
  int checks = 0;
  @override
  SyncAvailabilitySnapshot snapshot = const SyncAvailabilitySnapshot(
    status: SyncAvailabilityStatus.available,
  );
  void emit(SyncAvailabilityStatus status) {
    snapshot = SyncAvailabilitySnapshot(status: status);
    values.add(snapshot);
  }

  @override
  Stream<SyncAvailabilitySnapshot> get snapshots => values.stream;
  @override
  Future<void> checkNow() async {
    checks++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
