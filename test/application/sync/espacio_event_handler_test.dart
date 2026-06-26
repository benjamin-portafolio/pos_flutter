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
}
