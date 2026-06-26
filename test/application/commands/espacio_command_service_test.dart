import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/crear_espacio_command.dart';
import 'package:pos_flutter/application/commands/espacio_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/event_processor.dart';
import 'package:pos_flutter/application/sync/handlers/espacio_event_handler.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';

void main() {
  late AppDatabase db;
  late EspacioDao espacioDao;
  late EventDao eventDao;
  late EspacioCommandService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    espacioDao = EspacioDao(db);
    eventDao = EventDao(db);
    service = EspacioCommandService(
      db: db,
      eventDao: eventDao,
      eventRefDao: EventRefDao(db),
      eventProcessor: EventProcessor(
        espacioEventHandler: EspacioEventHandler(espacioDao),
      ),
      commandContext: const LocalCommandContext(
        deviceId: 'test_device',
        userId: 'test_user',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('crearEspacio guarda y aplica el evento solo localmente', () async {
    await service.crearEspacio(
      const CrearEspacioCommand(
        nombre: 'Terraza',
        identificacion: 'terraza',
        visibilidad: VisibilidadEspacio.sinRestriccion,
      ),
    );

    final espacios = await espacioDao.obtenerEspacios();
    final events = await eventDao.obtenerEventosPendientes();
    final refs = await db.select(db.eventRefs).get();

    expect(espacios, hasLength(1));
    expect(espacios.single.nombre, 'Terraza');
    expect(espacios.single.identificacion, 'terraza');

    expect(events, hasLength(1));
    expect(events.single.eventType, 'espacio_creado');
    expect(events.single.syncStatus, 'pending');

    expect(
      refs.map((ref) => ref.refType),
      containsAll(['espacio', 'espacio_identificacion']),
    );
  });
}
