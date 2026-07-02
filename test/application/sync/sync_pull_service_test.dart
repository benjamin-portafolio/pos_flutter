import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_registry.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  late AppDatabase db;
  late EspacioDao espacioDao;
  late SyncCheckpointDao checkpointDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    espacioDao = EspacioDao(db);
    checkpointDao = SyncCheckpointDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('pullAvailableEvents aplica eventos y avanza checkpoint', () async {
    final service = SyncPullService(
      db: db,
      syncCheckpointDao: checkpointDao,
      eventProcessor: EventProcessor(
        handlers: espacioEventHandlers(EspacioEventHandler(espacioDao)),
      ),
      endpointConfig: SyncEndpointConfig(
        initialBaseUrl: 'http://localhost:3000',
      ),
      commandContext: const LocalCommandContext(
        deviceId: 'device_tablet_01',
        userId: 'user_01',
      ),
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/sync/pull');
        expect(request.url.queryParameters['since'], '0');
        expect(request.url.queryParameters['limit'], '500');

        return http.Response(
          jsonEncode({
            'events': [
              _remoteEspacioEvent(
                eventId: 'event_4',
                aggregateId: 'espacio_4',
                serverSequence: 4,
                nombre: 'Salon',
              ),
              _remoteEspacioEvent(
                eventId: 'event_5',
                aggregateId: 'espacio_5',
                serverSequence: 5,
                nombre: 'Terraza',
              ),
            ],
            'next_cursor': 5,
            'has_more': false,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final report = await service.pullAvailableEvents();
    final espacios = await espacioDao.obtenerEspacios();
    final events = await db.select(db.events).get();
    final checkpoint = await checkpointDao.obtenerLastFullPullServerSequence();

    expect(report.total, 2);
    expect(report.lastCursor, 5);
    expect(checkpoint, 5);
    expect(
      espacios.map((espacio) => espacio.id),
      containsAll(['espacio_4', 'espacio_5']),
    );
    expect(events.map((event) => event.syncStatus).toSet(), {'synced'});
    expect(events.map((event) => event.serverSequence), containsAll([4, 5]));
  });
}

Map<String, Object?> _remoteEspacioEvent({
  required String eventId,
  required String aggregateId,
  required int serverSequence,
  required String nombre,
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
      'nombre': nombre,
      'identificacion': null,
      'visibilidad': 'sin_restriccion',
    },
    'sync_status': 'synced',
  };
}
