import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/application/sync/sync_socket_listener.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  late AppDatabase db;
  late EventDao eventDao;
  late _FakeSyncPushService pushService;
  late _FakeSyncPullService pullService;
  late SyncOrchestrator orchestrator;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    eventDao = EventDao(db);
    pushService = _FakeSyncPushService();
    pullService = _FakeSyncPullService();
    orchestrator = SyncOrchestrator(
      eventDao: eventDao,
      pullService: pullService,
      pushService: pushService,
      socketListener: SyncSocketListener(
        endpointConfig: SyncEndpointConfig(),
        commandContext: const LocalCommandContext(
          deviceId: 'test_device',
          userId: 'test_user',
        ),
        syncCheckpointDao: SyncCheckpointDao(db),
      ),
    );
  });

  tearDown(() async {
    await orchestrator.stopAutoPush();
    await db.close();
  });

  test('hace push automatico cuando aparece un evento pending', () async {
    orchestrator.startAutoPush();

    await eventDao.insertarEvento(
      EventsCompanion.insert(
        eventId: 'event_1',
        aggregateType: 'espacio',
        aggregateId: 'espacio_1',
        eventType: 'espacio_creado',
        deviceId: 'test_device',
        userId: 'test_user',
        createdAtLocal: DateTime(2026),
        payload: '{}',
        baseVersion: const Value(1),
      ),
    );

    await pushService.firstPush.future.timeout(const Duration(seconds: 1));
    await pullService.firstPull.future.timeout(const Duration(seconds: 1));

    expect(pushService.pushCount, greaterThanOrEqualTo(1));
    expect(pullService.pullCount, greaterThanOrEqualTo(1));
  });
}

class _FakeSyncPushService implements SyncPushService {
  final firstPush = Completer<void>();
  var pushCount = 0;

  @override
  Future<SyncPushReport> pushPendingEvents() async {
    pushCount++;
    if (!firstPush.isCompleted) {
      firstPush.complete();
    }

    return const SyncPushReport(
      total: 1,
      synced: 1,
      rejected: 0,
      conflicts: 0,
      pending: 0,
    );
  }

  @override
  Future<SyncConnectionCheck> testConnection() async {
    return const SyncConnectionCheck(statusCode: 200, body: '');
  }
}

class _FakeSyncPullService implements SyncPullService {
  final firstPull = Completer<void>();
  var pullCount = 0;
  int? latestServerSequence;

  @override
  Future<SyncPullReport> pullAvailableEvents({
    int limit = SyncPullService.defaultLimit,
  }) async {
    pullCount++;
    if (!firstPull.isCompleted) {
      firstPull.complete();
    }
    return const SyncPullReport(total: 0, lastCursor: 0, hasMore: false);
  }

  @override
  Future<SyncPullReport> pullIfBehind(int latestServerSequence) async {
    this.latestServerSequence = latestServerSequence;
    pullCount++;
    if (!firstPull.isCompleted) {
      firstPull.complete();
    }
    return SyncPullReport(
      total: 0,
      lastCursor: latestServerSequence,
      hasMore: false,
    );
  }
}
