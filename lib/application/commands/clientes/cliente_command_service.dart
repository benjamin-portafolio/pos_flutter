import 'package:uuid/uuid.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/cliente_creado_payload.dart';
import '../local_command_context.dart';
import 'crear_cliente_command.dart';

class ClienteCommandService {
  ClienteCommandService({
    required LocalEventStore eventStore,
    required LocalCommandContext commandContext,
  }) : _eventStore = eventStore,
       _context = commandContext;
  final LocalEventStore _eventStore;
  final LocalCommandContext _context;
  final Uuid _uuid = const Uuid();

  Future<void> crearCliente(CrearClienteCommand command) async {
    final payload = ClienteCreadoPayload.fromJson({
      'nombre': command.nombre,
      'telefono': command.telefono,
    });
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: ClienteCreadoPayload.aggregateType,
      aggregateId: _uuid.v4(),
      eventType: ClienteCreadoPayload.eventType,
      deviceId: _context.deviceId,
      userId: _context.userId,
      baseVersion: 1,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );
    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(
          refType: ClienteCreadoPayload.aggregateType,
          refId: event.aggregateId,
        ),
      ],
    );
  }
}
