import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/drift_local_event_store.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';

void main() {
  late AppDatabase db;
  late EspacioDao espacioDao;
  late EventDao eventDao;
  late DriftLocalEventStore eventStore;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    espacioDao = EspacioDao(db);
    eventDao = EventDao(db);
    eventStore = DriftLocalEventStore(
      db: db,
      eventDao: eventDao,
      eventRefDao: EventRefDao(db),
      eventProcessor: EventProcessor(
        espacioEventHandler: EspacioEventHandler(espacioDao),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'appendAndApply guarda evento, referencias y aplica proyeccion',
    () async {
      final event = SyncEvent(
        eventId: 'event-1',
        aggregateType: 'espacio',
        aggregateId: 'espacio-1',
        eventType: 'espacio_creado',
        deviceId: 'test_device',
        userId: 'test_user',
        baseVersion: 1,
        createdAtLocal: DateTime(2026),
        payload: const {
          'nombre': 'Terraza',
          'identificacion': 'terraza',
          'visibilidad': 'sin_restriccion',
        },
      );

      await eventStore.appendAndApply(
        event,
        refs: const [
          LocalEventRef.affects(refType: 'espacio', refId: 'espacio-1'),
          LocalEventRef.requiresUnique(
            refType: 'espacio_identificacion',
            refId: 'terraza',
          ),
        ],
      );

      final espacios = await espacioDao.obtenerEspacios();
      final events = await eventDao.obtenerEventosPendientes();
      final refs = await db.select(db.eventRefs).get();

      expect(espacios, hasLength(1));
      expect(espacios.single.id, 'espacio-1');
      expect(espacios.single.nombre, 'Terraza');
      expect(espacios.single.identificacion, 'terraza');
      expect(espacios.single.visibilidad, VisibilidadEspacio.sinRestriccion);

      expect(events, hasLength(1));
      expect(events.single.eventId, 'event-1');
      expect(events.single.eventType, 'espacio_creado');
      expect(events.single.syncStatus, 'pending');
      expect(
        jsonDecode(events.single.payload),
        containsPair('visibilidad', 'sin_restriccion'),
      );

      expect(refs, hasLength(2));
      expect(
        refs.map((ref) => ref.refType),
        containsAll(['espacio', 'espacio_identificacion']),
      );
      expect(
        refs.map((ref) => ref.relationship),
        containsAll(['affects', 'requires_unique']),
      );
      expect(refs.map((ref) => ref.source).toSet(), {'local_pending'});
    },
  );
}
