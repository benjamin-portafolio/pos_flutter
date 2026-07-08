import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/sync_conflict_projection_cleaner.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_push_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';

void main() {
  late AppDatabase db;
  late EspacioDao espacioDao;
  late EventDao eventDao;
  late EventRefDao eventRefDao;
  late SyncCheckpointDao checkpointDao;
  late DriftSyncPersistence syncPersistence;
  late DriftEspacioProjectionStore espacioProjectionStore;
  late DriftLocalEventStore localEventStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    espacioDao = EspacioDao(db);
    eventDao = EventDao(db);
    eventRefDao = EventRefDao(db);
    checkpointDao = SyncCheckpointDao(db);
    syncPersistence = DriftSyncPersistence(
      eventDao: eventDao,
      eventRefDao: eventRefDao,
      syncCheckpointDao: checkpointDao,
    );
    espacioProjectionStore = DriftEspacioProjectionStore(
      espacioDao: espacioDao,
    );
    localEventStore = DriftLocalEventStore(
      db: db,
      eventDao: eventDao,
      eventRefDao: eventRefDao,
      eventProcessor: EventProcessor(
        handlers: espacioEventHandlers(
          EspacioEventHandler(espacioProjectionStore),
        ),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('duplicate con original_sync_status conflict no marca synced', () async {
    await localEventStore.appendAndApply(
      _localEspacioEvent(),
      refs: const [
        LocalEventRef.affects(refType: 'espacio', refId: 'local_space_1'),
        LocalEventRef.requiresUnique(
          refType: 'espacio_identificacion',
          refId: 'terraza',
        ),
      ],
    );

    final service = SyncPushService(
      syncPersistence: syncPersistence,
      endpointConfig: SyncEndpointConfig(
        initialBaseUrl: 'http://localhost:3000',
      ),
      conflictProjectionCleaner: SyncConflictProjectionCleaner(
        espacioProjectionStore: espacioProjectionStore,
      ),
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/sync/push');

        return http.Response(
          jsonEncode({
            'results': [
              {
                'event_id': 'local_event_1',
                'status': 'duplicate',
                'original_sync_status': 'conflict',
                'server_sequence': 13,
                'created_at_server': '2026-06-09T20:31:00.000Z',
                'reason': 'Ya existe un espacio con identificacion terraza.',
              },
            ],
            'server_time': '2026-06-09T20:31:00.000Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final report = await service.pushPendingEvents();
    final event = (await db.select(db.events).get()).single;
    final refs = await db.select(db.eventRefs).get();
    final espacios = await espacioDao.obtenerEspacios();

    expect(report.synced, 0);
    expect(report.conflicts, 1);
    expect(event.syncStatus, 'conflict');
    expect(event.serverSequence, 13);
    expect(event.rejectionReason, contains('identificacion terraza'));
    expect(refs.map((ref) => ref.source).toSet(), {'server'});
    expect(refs.map((ref) => ref.serverSequence).toSet(), {13});
    expect(espacios, isEmpty);
  });
}

SyncEvent _localEspacioEvent() {
  return SyncEvent(
    eventId: 'local_event_1',
    aggregateType: 'espacio',
    aggregateId: 'local_space_1',
    eventType: 'espacio_creado',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.parse('2026-06-09T20:30:00.000Z'),
    baseVersion: 1,
    payload: const {
      'nombre': 'Terraza',
      'identificacion': 'terraza',
      'visibilidad': 'sin_restriccion',
    },
  );
}
