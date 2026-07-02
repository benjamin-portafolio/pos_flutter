import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';

void main() {
  late AppDatabase db;
  late EspacioDao espacioDao;
  late EspacioEventHandler handler;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    espacioDao = EspacioDao(db);
    handler = EspacioEventHandler(espacioDao);
  });

  tearDown(() async {
    await db.close();
  });

  test('applyEspacioCreado acepta visibilidad legada por indice', () async {
    await handler.applyEspacioCreado(
      SyncEvent(
        eventId: 'event_1',
        aggregateType: 'espacio',
        aggregateId: 'espacio_1',
        eventType: 'espacio_creado',
        deviceId: 'test_device',
        userId: 'test_user',
        baseVersion: 1,
        createdAtLocal: DateTime(2026),
        payload: const {
          'nombre': 'Salon',
          'identificacion': null,
          'visibilidad': 1,
        },
      ),
    );

    final espacio = await espacioDao.obtenerEspacioPorId('espacio_1');

    expect(espacio, isNotNull);
    expect(espacio!.visibilidad, VisibilidadEspacio.soloRestringido);
  });

  test('applyEspacioCreado es idempotente para el mismo evento', () async {
    final event = SyncEvent(
      eventId: 'event_1',
      aggregateType: 'espacio',
      aggregateId: 'espacio_1',
      eventType: 'espacio_creado',
      deviceId: 'test_device',
      userId: 'test_user',
      baseVersion: 1,
      createdAtLocal: DateTime(2026),
      payload: const {
        'nombre': 'Salon',
        'identificacion': 'salon',
        'visibilidad': 'sin_restriccion',
      },
    );

    await handler.applyEspacioCreado(event);
    await handler.applyEspacioCreado(event);

    final espacios = await espacioDao.obtenerEspacios();

    expect(espacios, hasLength(1));
    expect(espacios.single.createdEventId, 'event_1');
  });

  test('applyEspacioCreado completa metadata cuando llega por pull', () async {
    final localEvent = SyncEvent(
      eventId: 'event_1',
      aggregateType: 'espacio',
      aggregateId: 'espacio_1',
      eventType: 'espacio_creado',
      deviceId: 'test_device',
      userId: 'test_user',
      baseVersion: 1,
      createdAtLocal: DateTime(2026),
      payload: const {
        'nombre': 'Salon',
        'identificacion': 'salon',
        'visibilidad': 'sin_restriccion',
      },
    );

    await handler.applyEspacioCreado(localEvent);
    await handler.applyEspacioCreado(
      SyncEvent(
        eventId: localEvent.eventId,
        aggregateType: localEvent.aggregateType,
        aggregateId: localEvent.aggregateId,
        eventType: localEvent.eventType,
        deviceId: localEvent.deviceId,
        userId: localEvent.userId,
        baseVersion: localEvent.baseVersion,
        serverSequence: 5,
        createdAtLocal: localEvent.createdAtLocal,
        createdAtServer: DateTime(2026, 1, 1, 12),
        payload: localEvent.payload,
        syncStatus: 'synced',
      ),
    );

    final espacios = await espacioDao.obtenerEspacios();

    expect(espacios, hasLength(1));
    expect(espacios.single.lastServerSequence, 5);
    expect(espacios.single.lastEventId, 'event_1');
  });

  test('applyEspacioCreado rechaza identificacion duplicada', () async {
    await handler.applyEspacioCreado(
      SyncEvent(
        eventId: 'event_1',
        aggregateType: 'espacio',
        aggregateId: 'espacio_1',
        eventType: 'espacio_creado',
        deviceId: 'test_device',
        userId: 'test_user',
        baseVersion: 1,
        createdAtLocal: DateTime(2026),
        payload: const {
          'nombre': 'Salon',
          'identificacion': 'salon',
          'visibilidad': 'sin_restriccion',
        },
      ),
    );

    await expectLater(
      handler.applyEspacioCreado(
        SyncEvent(
          eventId: 'event_2',
          aggregateType: 'espacio',
          aggregateId: 'espacio_2',
          eventType: 'espacio_creado',
          deviceId: 'test_device',
          userId: 'test_user',
          baseVersion: 1,
          createdAtLocal: DateTime(2026),
          payload: const {
            'nombre': 'Otro salon',
            'identificacion': 'salon',
            'visibilidad': 'sin_restriccion',
          },
        ),
      ),
      throwsA(isA<StateError>()),
    );

    final espacios = await espacioDao.obtenerEspacios();

    expect(espacios, hasLength(1));
    expect(espacios.single.id, 'espacio_1');
  });

  test(
    'espacios protege identificaciones duplicadas con indice local',
    () async {
      await espacioDao.insertarEspacio(
        EspaciosCompanion.insert(
          id: 'espacio_1',
          nombre: 'Salon',
          identificacion: const Value('salon'),
          visibilidad: VisibilidadEspacio.sinRestriccion,
          createdEventId: const Value('event_1'),
        ),
      );

      await expectLater(
        espacioDao.insertarEspacio(
          EspaciosCompanion.insert(
            id: 'espacio_2',
            nombre: 'Otro salon',
            identificacion: const Value('salon'),
            visibilidad: VisibilidadEspacio.sinRestriccion,
            createdEventId: const Value('event_2'),
          ),
        ),
        throwsA(isA<Exception>()),
      );
    },
  );
}
