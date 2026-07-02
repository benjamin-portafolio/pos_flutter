import 'dart:collection';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_health_service.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  late AppDatabase db;
  late _FakeSyncHealthService healthService;
  late _FakeSyncOrchestrator orchestrator;
  late SyncAvailabilityMonitor monitor;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    healthService = _FakeSyncHealthService();
    orchestrator = _FakeSyncOrchestrator();
    monitor = SyncAvailabilityMonitor(
      eventDao: EventDao(db),
      healthService: healthService,
      orchestrator: orchestrator,
      retryDelays: const [Duration(milliseconds: 20)],
    );
  });

  tearDown(() async {
    await monitor.dispose();
    await db.close();
  });

  test('health disponible inicia realtime, pull y push', () async {
    healthService.responses.add(_availableHealth(latestServerSequence: 7));

    await monitor.checkNow();

    expect(orchestrator.startRealtimeCount, 1);
    expect(orchestrator.pullIfBehindTargets, [7]);
    expect(orchestrator.pushCount, 1);
    expect(monitor.snapshot.status, SyncAvailabilityStatus.available);
  });

  test('un acceso correcto cancela el retry pendiente del backoff', () async {
    healthService.responses
      ..add(const SyncHealthException('Servidor sin respuesta.'))
      ..add(_availableHealth(latestServerSequence: 0));

    await monitor.checkNow();

    expect(monitor.snapshot.status, SyncAvailabilityStatus.unavailable);
    expect(orchestrator.stopRealtimeCount, 1);

    await monitor.checkNow();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(healthService.checkCount, 2);
    expect(monitor.snapshot.status, SyncAvailabilityStatus.available);
    expect(orchestrator.startRealtimeCount, 1);
  });
}

SyncHealthCheck _availableHealth({required int latestServerSequence}) {
  return SyncHealthCheck(
    statusCode: 200,
    body: '',
    status: 'ok',
    apiVersion: SyncHealthService.supportedApiVersion,
    latestServerSequence: latestServerSequence,
    serverTime: DateTime(2026),
  );
}

class _FakeSyncHealthService implements SyncHealthService {
  final responses = Queue<Object>();
  var checkCount = 0;

  @override
  Future<SyncHealthCheck> check() async {
    checkCount++;
    final response = responses.isEmpty
        ? _availableHealth(latestServerSequence: 0)
        : responses.removeFirst();

    if (response is SyncHealthException) throw response;

    return response as SyncHealthCheck;
  }
}

class _FakeSyncOrchestrator implements SyncOrchestrator {
  var startRealtimeCount = 0;
  var stopRealtimeCount = 0;
  var pushCount = 0;
  var pullCount = 0;
  final pullIfBehindTargets = <int>[];

  @override
  void startRealtimeListener() {
    startRealtimeCount++;
  }

  @override
  void stopRealtimeListener() {
    stopRealtimeCount++;
  }

  @override
  Future<SyncHealthCheck> testConnection() async {
    return _availableHealth(latestServerSequence: 0);
  }

  @override
  Future<SyncPullReport> pullAvailableEvents() async {
    pullCount++;
    return const SyncPullReport(total: 0, lastCursor: 0, hasMore: false);
  }

  @override
  Future<SyncPullReport> pullIfBehind(int latestServerSequence) async {
    pullIfBehindTargets.add(latestServerSequence);
    return SyncPullReport(
      total: 0,
      lastCursor: latestServerSequence,
      hasMore: false,
    );
  }

  @override
  Future<SyncPushReport> pushPendingEvents() async {
    pushCount++;
    return const SyncPushReport.empty();
  }
}
