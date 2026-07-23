import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/categoria_event_registry.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_registry.dart';
import 'package:pos_flutter/application/sync/remote_event_applier.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_categoria_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_espacio_projection_store.dart';
import 'package:pos_flutter/data/local/drift/drift_sync_persistence.dart';
import 'package:pos_flutter/data/local/drift/drift_synced_event_store.dart';

void main() {
  late AppDatabase db;
  late CategoriaDao categoriaDao;
  late EspacioDao espacioDao;
  late SyncCheckpointDao checkpointDao;
  late DriftSyncPersistence syncPersistence;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    categoriaDao = CategoriaDao(db);
    espacioDao = EspacioDao(db);
    checkpointDao = SyncCheckpointDao(db);
    syncPersistence = DriftSyncPersistence(
      eventDao: EventDao(db),
      eventRefDao: EventRefDao(db),
      syncCheckpointDao: checkpointDao,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('pullAvailableEvents aplica eventos y avanza checkpoint', () async {
    final eventProcessor = EventProcessor(
      handlers: {
        ...espacioEventHandlers(
          EspacioEventHandler(
            DriftEspacioProjectionStore(espacioDao: espacioDao),
          ),
        ),
        ...categoriaEventHandlers(
          CategoriaEventHandler(
            DriftCategoriaProjectionStore(categoriaDao: categoriaDao),
          ),
        ),
      },
    );
    final service = SyncPullService(
      syncPersistence: syncPersistence,
      remoteEventApplier: RemoteEventApplier(
        eventStore: DriftSyncedEventStore(db: db),
        eventProcessor: eventProcessor,
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
              _remoteCategoriaEvent(
                eventId: 'event_6',
                aggregateId: 'category_6',
                serverSequence: 6,
              ),
            ],
            'next_cursor': 6,
            'has_more': false,
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final report = await service.pullAvailableEvents();
    final espacios = await espacioDao.obtenerEspacios();
    final categorias = await categoriaDao.obtenerCategorias();
    final events = await db.select(db.events).get();
    final checkpoint = await checkpointDao.obtenerLastFullPullServerSequence();

    expect(report.total, 3);
    expect(report.lastCursor, 6);
    expect(checkpoint, 6);
    expect(
      espacios.map((espacio) => espacio.id),
      containsAll(['espacio_4', 'espacio_5']),
    );
    expect(categorias.single.id, 'category_6');
    expect(categorias.single.name, 'Bebidas');
    expect(events.map((event) => event.deliveryStatus).toSet(), {'delivered'});
    expect(events.map((event) => event.serverSequence), containsAll([4, 5, 6]));
  });
}

Map<String, Object?> _remoteCategoriaEvent({
  required String eventId,
  required String aggregateId,
  required int serverSequence,
}) {
  return {
    'event_id': eventId,
    'aggregate_type': 'category',
    'aggregate_id': aggregateId,
    'event_type': 'categoria_creada',
    'device_id': 'device_tablet_02',
    'user_id': 'user_02',
    'local_sequence': 2,
    'server_sequence': serverSequence,
    'base_server_sequence': null,
    'base_version': 1,
    'created_at_local': '2026-06-09T20:30:00.000Z',
    'created_at_server': '2026-06-09T20:31:00.000Z',
    'payload': {'name': 'Bebidas', 'color_key': 'cyan', 'sort_order': null},
    'sync_status': 'synced',
  };
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
