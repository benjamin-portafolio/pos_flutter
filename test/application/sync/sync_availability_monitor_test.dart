import 'dart:async';
import 'dart:collection';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/device_wifi_connectivity.dart';
import 'package:pos_flutter/application/sync/exceptions/sync_health_exception.dart';
import 'package:pos_flutter/application/sync/models/sync_availability_snapshot.dart';
import 'package:pos_flutter/application/sync/models/sync_health_check.dart';
import 'package:pos_flutter/application/sync/models/sync_pull_report.dart';
import 'package:pos_flutter/application/sync/models/sync_push_report.dart';
import 'package:pos_flutter/application/sync/sync_availability_monitor.dart';
import 'package:pos_flutter/application/sync/sync_health_service.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_server_detection_config.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';

void main() {
  late AppDatabase db;
  late EventDao eventDao;
  late DriftSyncPersistence syncPersistence;
  late _FakeSyncHealthService healthService;
  late _FakeSyncOrchestrator orchestrator;
  late SyncServerDetectionConfig serverDetectionConfig;
  late _FakeDeviceWifiConnectivity wifiConnectivity;
  late SyncAvailabilityMonitor monitor;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    eventDao = EventDao(db);
    syncPersistence = DriftSyncPersistence(
      db: db,
      eventDao: eventDao,
      eventRefDao: EventRefDao(db),
      syncCheckpointDao: SyncCheckpointDao(db),
    );
    healthService = _FakeSyncHealthService();
    orchestrator = _FakeSyncOrchestrator();
    serverDetectionConfig = SyncServerDetectionConfig();
    wifiConnectivity = _FakeDeviceWifiConnectivity(isWifiConnected: true);
    monitor = SyncAvailabilityMonitor(
      syncPersistence: syncPersistence,
      healthService: healthService,
      orchestrator: orchestrator,
      serverDetectionConfig: serverDetectionConfig,
      wifiConnectivity: wifiConnectivity,
      retryDelays: const [Duration(milliseconds: 20)],
    );
  });

  tearDown(() async {
    await monitor.dispose();
    await serverDetectionConfig.dispose();
    await wifiConnectivity.dispose();
    await db.close();
  });

  test('health disponible sin pendientes inicia realtime y pull', () async {
    healthService.responses.add(_availableHealth(latestServerSequence: 7));

    await monitor.checkNow();

    expect(orchestrator.startRealtimeCount, 1);
    expect(orchestrator.syncCalls, ['pullIfBehind:7']);
    expect(orchestrator.pullIfBehindTargets, [7]);
    expect(orchestrator.pushCount, 0);
    expect(monitor.snapshot.status, SyncAvailabilityStatus.available);
  });

  test(
    'health disponible con pendientes ejecuta push sin pull previo',
    () async {
      await eventDao.insertarEvento(
        EventsCompanion.insert(
          eventId: 'event-1',
          aggregateType: 'espacio',
          aggregateId: 'espacio-1',
          eventType: 'espacio_creado',
          deviceId: 'device-1',
          userId: 'user-1',
          createdAtLocal: DateTime(2026),
          payload: '{}',
        ),
      );
      healthService.responses.add(_availableHealth(latestServerSequence: 7));

      await monitor.checkNow();

      expect(orchestrator.startRealtimeCount, 1);
      expect(orchestrator.syncCalls, ['push']);
      expect(orchestrator.pullIfBehindTargets, isEmpty);
      expect(orchestrator.pushLatestServerSequences, [7]);
      expect(orchestrator.pushCount, 1);
      expect(monitor.snapshot.status, SyncAvailabilityStatus.available);
    },
  );

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

  test(
    'con deteccion por WiFi no hace health si WiFi no esta conectado',
    () async {
      serverDetectionConfig.updateRequireWifiForServerDetection(true);
      wifiConnectivity.setConnected(false);

      await monitor.checkNow();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(healthService.checkCount, 0);
      expect(orchestrator.stopRealtimeCount, 1);
      expect(monitor.snapshot.status, SyncAvailabilityStatus.unavailable);
      expect(monitor.snapshot.message, 'WiFi no disponible.');
      expect(monitor.snapshot.nextRetryAt, isNull);
    },
  );

  test('con deteccion por WiFi hace health cuando vuelve WiFi', () async {
    serverDetectionConfig.updateRequireWifiForServerDetection(true);
    wifiConnectivity.setConnected(false);
    healthService.responses.add(_availableHealth(latestServerSequence: 7));

    monitor.start();
    await monitor.checkNow();

    expect(healthService.checkCount, 0);

    wifiConnectivity.emitConnected(true);
    await healthService.nextCheck;
    await Future<void>.delayed(Duration.zero);

    expect(healthService.checkCount, 1);
    expect(orchestrator.syncCalls, ['pullIfBehind:7']);
    expect(monitor.snapshot.status, SyncAvailabilityStatus.available);
  });

  test(
    'con WiFi conectado conserva el backoff cuando el servidor no responde',
    () async {
      serverDetectionConfig.updateRequireWifiForServerDetection(true);
      wifiConnectivity.setConnected(true);
      healthService.responses
        ..add(const SyncHealthException('Servidor sin respuesta.'))
        ..add(_availableHealth(latestServerSequence: 0));

      await monitor.checkNow();

      expect(monitor.snapshot.status, SyncAvailabilityStatus.unavailable);
      expect(monitor.snapshot.nextRetryAt, isNotNull);

      await healthService.nextCheck;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(healthService.checkCount, 2);
      expect(monitor.snapshot.status, SyncAvailabilityStatus.available);
    },
  );
}

SyncHealthCheck _availableHealth({required int latestServerSequence}) {
  return SyncHealthCheck(
    statusCode: 200,
    body: '',
    status: 'ok',
    latestServerSequence: latestServerSequence,
    serverTime: DateTime(2026),
  );
}

class _FakeSyncHealthService implements SyncHealthService {
  final responses = Queue<Object>();
  Completer<void> _nextCheck = Completer<void>();
  var checkCount = 0;

  Future<void> get nextCheck => _nextCheck.future;

  @override
  Future<SyncHealthCheck> check() async {
    checkCount++;
    if (!_nextCheck.isCompleted) {
      _nextCheck.complete();
    }
    _nextCheck = Completer<void>();

    final response = responses.isEmpty
        ? _availableHealth(latestServerSequence: 0)
        : responses.removeFirst();

    if (response is SyncHealthException) throw response;

    return response as SyncHealthCheck;
  }
}

class _FakeDeviceWifiConnectivity implements DeviceWifiConnectivity {
  _FakeDeviceWifiConnectivity({required bool isWifiConnected})
    : _isWifiConnected = isWifiConnected;

  final _changes = StreamController<bool>.broadcast();
  bool _isWifiConnected;

  @override
  Future<bool> isWifiConnected() async => _isWifiConnected;

  @override
  Stream<bool> get wifiConnectionChanges => _changes.stream;

  void setConnected(bool value) {
    _isWifiConnected = value;
  }

  void emitConnected(bool value) {
    _isWifiConnected = value;
    _changes.add(value);
  }

  Future<void> dispose() async {
    await _changes.close();
  }
}

class _FakeSyncOrchestrator implements SyncOrchestrator {
  var startRealtimeCount = 0;
  var stopRealtimeCount = 0;
  var pushCount = 0;
  var pullCount = 0;
  final syncCalls = <String>[];
  final pullIfBehindTargets = <int>[];
  final pushLatestServerSequences = <int?>[];

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
    syncCalls.add('pullAvailable');
    return const SyncPullReport(total: 0, lastCursor: 0, hasMore: false);
  }

  @override
  Future<SyncPullReport> pullIfBehind(int latestServerSequence) async {
    pullIfBehindTargets.add(latestServerSequence);
    syncCalls.add('pullIfBehind:$latestServerSequence');
    return SyncPullReport(
      total: 0,
      lastCursor: latestServerSequence,
      hasMore: false,
    );
  }

  @override
  Future<SyncPushReport> pushPendingEvents({int? latestServerSequence}) async {
    pushCount++;
    pushLatestServerSequences.add(latestServerSequence);
    syncCalls.add('push');
    return const SyncPushReport.empty();
  }
}
