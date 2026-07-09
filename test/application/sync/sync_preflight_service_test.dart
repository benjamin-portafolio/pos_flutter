import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_registry.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/application/sync/pending_event_revalidator.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_preflight_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';

void main() {
  late AppDatabase db;
  late EspacioDao espacioDao;
  late EventDao eventDao;
  late EventRefDao eventRefDao;
  late SyncCheckpointDao checkpointDao;
  late DriftSyncPersistence syncPersistence;
  late DriftEspacioProjectionStore espacioProjectionStore;
  late DriftLocalEventStore localEventStore;
  late RemoteEventApplier remoteEventApplier;
  late PendingEventRevalidator pendingEventRevalidator;

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
    final eventProcessor = EventProcessor(
      handlers: espacioEventHandlers(
        EspacioEventHandler(espacioProjectionStore),
      ),
    );
    localEventStore = DriftLocalEventStore(
      db: db,
      eventDao: eventDao,
      eventRefDao: eventRefDao,
      eventProcessor: eventProcessor,
    );
    remoteEventApplier = RemoteEventApplier(
      eventStore: DriftSyncedEventStore(db: db),
      eventProcessor: eventProcessor,
    );
    pendingEventRevalidator = PendingEventRevalidator(
      syncPersistence: syncPersistence,
      espacioProjectionStore: espacioProjectionStore,
    );
  });

  tearDown(() async {
    await db.close();
  });

  SyncPreflightService buildPreflightService({required http.Client client}) {
    return SyncPreflightService(
      syncPersistence: syncPersistence,
      endpointConfig: SyncEndpointConfig(
        initialBaseUrl: 'http://localhost:3000',
      ),
      commandContext: const LocalCommandContext(
        deviceId: 'device_tablet_01',
        userId: 'user_01',
      ),
      remoteEventApplier: remoteEventApplier,
      pendingEventRevalidator: pendingEventRevalidator,
      client: client,
    );
  }

  test('omite preflight cuando los pendientes solo declaran affects', () async {
    await localEventStore.appendAndApply(
      _localEspacioEvent(
        eventId: 'local_event_1',
        aggregateId: 'local_space_1',
        identificacion: null,
      ),
      refs: const [
        LocalEventRef.affects(refType: 'espacio', refId: 'local_space_1'),
      ],
    );

    final service = buildPreflightService(
      client: MockClient((_) async {
        throw StateError('No debe llamar /sync/preflight.');
      }),
    );

    final report = await service.preflightPendingEvents();

    expect(report.skipped, isTrue);
    expect(report.reason, 'not_required');
  });

  test(
    'omite request remoto si full pull ya cubre la ultima secuencia',
    () async {
      await localEventStore.appendAndApply(
        _localEspacioEvent(
          eventId: 'local_event_1',
          aggregateId: 'local_space_1',
          identificacion: 'terraza',
        ),
        refs: const [
          LocalEventRef.affects(refType: 'espacio', refId: 'local_space_1'),
          LocalEventRef.requiresUnique(
            refType: 'espacio_identificacion',
            refId: 'terraza',
          ),
        ],
      );
      await remoteEventApplier.applySyncedEvents([
        SyncEvent.fromJson(
          _remoteEspacioEvent(
            eventId: 'remote_event_1',
            aggregateId: 'remote_space_1',
            serverSequence: 10,
            identificacion: 'terraza',
          ),
        ),
      ]);
      await checkpointDao.actualizarLastFullPullServerSequence(10);

      final service = buildPreflightService(
        client: MockClient((_) async {
          throw StateError('No debe llamar /sync/preflight.');
        }),
      );

      final report = await service.preflightPendingEvents(
        latestServerSequence: 10,
      );
      final events = await db.select(db.events).get();

      expect(report.skipped, isTrue);
      expect(report.reason, 'server_sequence_current');
      expect(report.localConflicts, 1);
      expect(
        events
            .singleWhere((event) => event.eventId == 'local_event_1')
            .deliveryStatus,
        'conflict',
      );
    },
  );

  test('aplica evento remoto impactante y marca conflicto local', () async {
    await localEventStore.appendAndApply(
      _localEspacioEvent(
        eventId: 'local_event_1',
        aggregateId: 'local_space_1',
        identificacion: 'terraza',
      ),
      refs: const [
        LocalEventRef.affects(refType: 'espacio', refId: 'local_space_1'),
        LocalEventRef.requiresUnique(
          refType: 'espacio_identificacion',
          refId: 'terraza',
        ),
      ],
    );

    final service = buildPreflightService(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/sync/preflight');

        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['device_id'], 'device_tablet_01');
        expect(body['last_full_pull_server_sequence'], 0);

        final pendingRefs = body['pending_refs'] as List;
        final firstPendingRef = pendingRefs.single as Map<String, Object?>;
        final refs = firstPendingRef['refs'] as List;
        expect(
          refs.cast<Map>().map((ref) => ref['type']),
          contains('espacio_identificacion'),
        );

        return http.Response(
          jsonEncode({
            'events': [
              _remoteEspacioEvent(
                eventId: 'remote_event_1',
                aggregateId: 'remote_space_1',
                serverSequence: 9,
                identificacion: 'terraza',
              ),
            ],
            'preflight_sequence': 10,
            'has_more': false,
            'requires_full_pull_before_push': false,
            'reason': null,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final report = await service.preflightPendingEvents();
    final events = await db.select(db.events).get();
    final espacios = await espacioDao.obtenerEspacios();
    final lastPreflight = await checkpointDao
        .obtenerLastPreflightServerSequence();

    expect(report.localConflicts, 1);
    expect(report.impactingEvents, 1);
    expect(lastPreflight, 10);
    expect(
      events
          .singleWhere((event) => event.eventId == 'local_event_1')
          .deliveryStatus,
      'conflict',
    );
    expect(
      events
          .singleWhere((event) => event.eventId == 'remote_event_1')
          .deliveryStatus,
      'delivered',
    );
    expect(espacios, hasLength(1));
    expect(espacios.single.id, 'remote_space_1');
  });
}

SyncEvent _localEspacioEvent({
  required String eventId,
  required String aggregateId,
  required String? identificacion,
}) {
  return SyncEvent(
    eventId: eventId,
    aggregateType: 'espacio',
    aggregateId: aggregateId,
    eventType: 'espacio_creado',
    deviceId: 'device_tablet_01',
    userId: 'user_01',
    createdAtLocal: DateTime.parse('2026-06-09T20:30:00.000Z'),
    baseVersion: 1,
    payload: {
      'nombre': 'Terraza',
      'identificacion': identificacion,
      'visibilidad': 'sin_restriccion',
    },
  );
}

Map<String, Object?> _remoteEspacioEvent({
  required String eventId,
  required String aggregateId,
  required int serverSequence,
  required String? identificacion,
}) {
  return {
    'event_id': eventId,
    'aggregate_type': 'espacio',
    'aggregate_id': aggregateId,
    'event_type': 'espacio_creado',
    'device_id': 'device_tablet_02',
    'user_id': 'user_02',
    'local_sequence': 1,
    'server_sequence': serverSequence,
    'base_server_sequence': null,
    'base_version': 1,
    'created_at_local': '2026-06-09T20:30:00.000Z',
    'created_at_server': '2026-06-09T20:31:00.000Z',
    'payload': {
      'nombre': 'Terraza servidor',
      'identificacion': identificacion,
      'visibilidad': 'sin_restriccion',
    },
    'sync_status': 'synced',
  };
}
