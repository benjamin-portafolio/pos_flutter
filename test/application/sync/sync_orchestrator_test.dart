import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/models/sync_events_available_notice.dart';
import 'package:pos_flutter/application/sync/models/sync_preflight_report.dart';
import 'package:pos_flutter/application/sync/models/sync_pull_report.dart';
import 'package:pos_flutter/application/sync/models/sync_push_report.dart';
import 'package:pos_flutter/application/sync/sync_health_service.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_preflight_service.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/application/sync/sync_socket_listener.dart';

void main() {
  late _FakeSyncPreflightService preflightService;
  late _FakeSyncPullService pullService;
  late _FakeSyncSocketListener socketListener;
  late SyncOrchestrator orchestrator;

  setUp(() {
    preflightService = _FakeSyncPreflightService();
    pullService = _FakeSyncPullService();
    socketListener = _FakeSyncSocketListener();
    orchestrator = SyncOrchestrator(
      healthService: _FakeSyncHealthService(),
      preflightService: preflightService,
      pullService: pullService,
      pushService: _FakeSyncPushService(),
      socketListener: socketListener,
    );
  });

  tearDown(() async {
    orchestrator.stopRealtimeListener();
    await socketListener.dispose();
  });

  test('reconexion websocket dispara pull de eventos disponibles', () async {
    orchestrator.startRealtimeListener();

    socketListener.emitConnectionEstablished();
    await pullService.nextPullAvailable;

    expect(socketListener.startCount, 1);
    expect(pullService.pullAvailableCount, 1);
    expect(pullService.pullIfBehindTargets, isEmpty);
  });

  test('aviso realtime conserva pull incremental por secuencia', () async {
    orchestrator.startRealtimeListener();

    socketListener.emitEventsAvailable(latestServerSequence: 9);
    await pullService.nextPullIfBehind;

    expect(pullService.pullAvailableCount, 0);
    expect(pullService.pullIfBehindTargets, [9]);
  });

  test('push de pendientes propaga latestServerSequence a preflight', () async {
    await orchestrator.pushPendingEvents(latestServerSequence: 9);

    expect(preflightService.latestServerSequences, [9]);
  });
}

class _FakeSyncHealthService implements SyncHealthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncPushService implements SyncPushService {
  @override
  Future<SyncPushReport> pushPendingEvents() async {
    return const SyncPushReport.empty();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncPreflightService implements SyncPreflightService {
  @override
  Future<SyncPreflightReport> preflightPendingEvents({
    int maxEvents = SyncPreflightService.defaultMaxEvents,
    int? latestServerSequence,
  }) async {
    latestServerSequences.add(latestServerSequence);
    return const SyncPreflightReport.skipped(reason: 'no_pending_events');
  }

  final latestServerSequences = <int?>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncPullService implements SyncPullService {
  final pullIfBehindTargets = <int>[];
  var pullAvailableCount = 0;
  Completer<void> _nextPullAvailable = Completer<void>();
  Completer<void> _nextPullIfBehind = Completer<void>();

  Future<void> get nextPullAvailable => _nextPullAvailable.future;

  Future<void> get nextPullIfBehind => _nextPullIfBehind.future;

  @override
  Future<SyncPullReport> pullAvailableEvents({
    int limit = SyncPullService.defaultLimit,
  }) async {
    pullAvailableCount++;
    _completeAndResetPullAvailable();
    return const SyncPullReport(total: 0, lastCursor: 0, hasMore: false);
  }

  @override
  Future<SyncPullReport> pullIfBehind(int latestServerSequence) async {
    pullIfBehindTargets.add(latestServerSequence);
    _completeAndResetPullIfBehind();
    return SyncPullReport(
      total: 0,
      lastCursor: latestServerSequence,
      hasMore: false,
    );
  }

  void _completeAndResetPullAvailable() {
    if (!_nextPullAvailable.isCompleted) {
      _nextPullAvailable.complete();
    }
    _nextPullAvailable = Completer<void>();
  }

  void _completeAndResetPullIfBehind() {
    if (!_nextPullIfBehind.isCompleted) {
      _nextPullIfBehind.complete();
    }
    _nextPullIfBehind = Completer<void>();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSyncSocketListener implements SyncSocketListener {
  final _eventsAvailableController =
      StreamController<SyncEventsAvailableNotice>.broadcast();
  final _connectionEstablishedController = StreamController<void>.broadcast();
  var startCount = 0;
  var stopCount = 0;
  var _isActive = false;

  @override
  bool get isActive => _isActive;

  @override
  Stream<SyncEventsAvailableNotice> get eventsAvailable =>
      _eventsAvailableController.stream;

  @override
  Stream<void> get connectionEstablished =>
      _connectionEstablishedController.stream;

  @override
  void start() {
    startCount++;
    _isActive = true;
  }

  @override
  void stop() {
    stopCount++;
    _isActive = false;
  }

  void emitConnectionEstablished() {
    _connectionEstablishedController.add(null);
  }

  void emitEventsAvailable({required int latestServerSequence}) {
    _eventsAvailableController.add(
      SyncEventsAvailableNotice(
        latestServerSequence: latestServerSequence,
        eventTypes: const ['espacio_creado'],
        sourceDeviceId: 'other_device',
      ),
    );
  }

  Future<void> dispose() async {
    await _eventsAvailableController.close();
    await _connectionEstablishedController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
