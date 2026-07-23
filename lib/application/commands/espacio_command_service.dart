import 'package:uuid/uuid.dart';

import '../../domain/espacios/identificacion_espacio.dart';
import '../../domain/espacios/nombre_espacio.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../sync/payloads/espacio_creado_payload.dart';
import 'crear_espacio_command.dart';
import 'local_command_context.dart';

class EspacioCommandService {
  EspacioCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
  }) : _eventStore = eventStore,
       _commandContext = commandContext;

  final LocalEventStore _eventStore;
  final LocalCommandContext _commandContext;
  final Uuid _uuid = const Uuid();

  Future<void> crearEspacio(CrearEspacioCommand command) async {
    final nombre = NombreEspacio.fromInput(command.nombre);
    final identificacion = IdentificacionEspacio.fromOptionalInput(
      command.identificacion,
    );
    final espacioId = _uuid.v4();
    final payload = EspacioCreadoPayload(
      nombre: nombre.value,
      identificacion: identificacion?.value,
      visibilidad: command.visibilidad,
    );
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: EspacioCreadoPayload.aggregateType,
      aggregateId: espacioId,
      eventType: EspacioCreadoPayload.eventType,
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );

    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(refType: 'espacio', refId: event.aggregateId),
        if (identificacion != null)
          LocalEventRef.requiresUnique(
            refType: 'espacio_identificacion',
            refId: identificacion.value,
          ),
      ],
    );
  }
}
