import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_orchestrator.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/application/sync/sync_socket_listener.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  late AppDatabase db;
  late EventDao eventDao;
  late _FakeSyncPushService pushService;
  late SyncOrchestrator orchestrator;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    eventDao = EventDao(db);
    pushService = _FakeSyncPushService();
    orchestrator = SyncOrchestrator(
      eventDao: eventDao,
      pushService: pushService,
      socketListener: SyncSocketListener(
        endpointConfig: SyncEndpointConfig(),
        commandContext: const LocalCommandContext(
          deviceId: 'test_device',
          userId: 'test_user',
        ),
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

    expect(pushService.pushCount, greaterThanOrEqualTo(1));
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

    return const SyncPushReport.empty();
  }

  @override
  Future<SyncConnectionCheck> testConnection() async {
    return const SyncConnectionCheck(statusCode: 200, body: '');
  }
}
