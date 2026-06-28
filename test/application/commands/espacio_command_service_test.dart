import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/crear_espacio_command.dart';
import 'package:pos_flutter/application/commands/espacio_command_service.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/sync/local_event_store.dart';
import 'package:pos_flutter/application/sync/models/sync_event.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';

void main() {
  late _CapturingLocalEventStore eventStore;
  late EspacioCommandService service;

  setUp(() {
    eventStore = _CapturingLocalEventStore();
    service = EspacioCommandService(
      eventStore: eventStore,
      commandContext: const LocalCommandContext(
        deviceId: 'test_device',
        userId: 'test_user',
      ),
    );
  });

  test('crearEspacio crea el evento y sus referencias de negocio', () async {
    await service.crearEspacio(
      const CrearEspacioCommand(
        nombre: ' Terraza ',
        identificacion: ' terraza ',
        visibilidad: VisibilidadEspacio.sinRestriccion,
      ),
    );

    final event = eventStore.event!;
    final refs = eventStore.refs;

    expect(event.aggregateType, 'espacio');
    expect(event.aggregateId, isNotEmpty);
    expect(event.eventType, 'espacio_creado');
    expect(event.deviceId, 'test_device');
    expect(event.userId, 'test_user');
    expect(event.baseVersion, 1);
    expect(event.payload, {
      'nombre': 'Terraza',
      'identificacion': 'terraza',
      'visibilidad': 'sin_restriccion',
    });

    expect(refs, hasLength(2));
    expect(refs[0].refType, 'espacio');
    expect(refs[0].refId, event.aggregateId);
    expect(refs[0].relationship, 'affects');
    expect(refs[1].refType, 'espacio_identificacion');
    expect(refs[1].refId, 'terraza');
    expect(refs[1].relationship, 'requires_unique');
  });

  test(
    'crearEspacio omite la referencia unica si no hay identificacion valida',
    () async {
      await service.crearEspacio(
        const CrearEspacioCommand(
          nombre: 'Salon',
          identificacion: '   ',
          visibilidad: VisibilidadEspacio.sinRestriccion,
        ),
      );

      expect(eventStore.refs, hasLength(1));
      expect(eventStore.refs.single.refType, 'espacio');
      expect(eventStore.refs.single.relationship, 'affects');
    },
  );

  test('crearEspacio rechaza nombres sin contenido', () async {
    await expectLater(
      service.crearEspacio(
        const CrearEspacioCommand(
          nombre: '   ',
          identificacion: 'salon',
          visibilidad: VisibilidadEspacio.sinRestriccion,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(eventStore.event, isNull);
    expect(eventStore.refs, isEmpty);
  });
}

class _CapturingLocalEventStore implements LocalEventStore {
  SyncEvent? event;
  List<LocalEventRef> refs = const [];

  @override
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  }) async {
    this.event = event;
    this.refs = refs;
  }
}
