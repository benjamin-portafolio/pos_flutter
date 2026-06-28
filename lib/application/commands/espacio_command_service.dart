import 'package:uuid/uuid.dart';

import 'crear_espacio_command.dart';
import 'local_command_context.dart';
import '../sync/local_event_store.dart';
import '../sync/models/sync_event.dart';
import '../../domain/espacios/visibilidad_espacio.dart';

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
    final espacioId = _uuid.v4();
    final identificacion = command.identificacion;
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: 'espacio',
      aggregateId: espacioId,
      eventType: 'espacio_creado',
      deviceId: _commandContext.deviceId,
      userId: _commandContext.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: {
        'nombre': command.nombre,
        'identificacion': identificacion,
        'visibilidad': command.visibilidad.eventValue,
      },
    );

    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(refType: 'espacio', refId: event.aggregateId),
        if (identificacion != null && identificacion.isNotEmpty)
          LocalEventRef.requiresUnique(
            refType: 'espacio_identificacion',
            refId: identificacion,
          ),
      ],
    );
  }
}
