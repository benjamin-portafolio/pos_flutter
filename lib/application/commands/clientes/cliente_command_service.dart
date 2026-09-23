import 'package:uuid/uuid.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/cliente_creado_payload.dart';
import '../local_command_context.dart';
import 'crear_cliente_command.dart';
import 'editar_cliente_command.dart';
import '../../sync/payloads/cliente_actualizado_payload.dart';
import '../../sync/projections/cliente_projection_store.dart';

class ClienteCommandService {
  ClienteCommandService({
    required LocalEventStore eventStore,
    required ClienteProjectionStore clienteProjectionStore,
    required LocalCommandContext commandContext,
  }) : _clientes = clienteProjectionStore,
       _eventStore = eventStore,
       _context = commandContext;
  final ClienteProjectionStore _clientes;
  final LocalEventStore _eventStore;
  final LocalCommandContext _context;
  final Uuid _uuid = const Uuid();

  Future<void> editarCliente(EditarClienteCommand command) async {
    final after = ClienteCreadoPayload.fromJson({
      'nombre': command.nombre,
      'telefono': command.telefono,
    });
    final current = await _clientes.findById(command.clienteId);
    if (current == null || !current.active) {
      throw StateError('El cliente no está disponible.');
    }
    if (current.lastEventId != command.baseEventId) {
      throw StateError('El cliente cambió desde que se abrió la edición.');
    }
    final before = ClienteCreadoPayload(
      nombre: current.nombre,
      telefono: current.telefono,
    );
    if (ClienteActualizadoPayload.sameState(before, after)) return;
    final payload = ClienteActualizadoPayload(
      baseEventId: command.baseEventId,
      before: before,
      after: after,
    );
    final event = SyncEvent(
      eventId: _uuid.v4(),
      aggregateType: ClienteActualizadoPayload.aggregateType,
      aggregateId: current.id,
      eventType: ClienteActualizadoPayload.eventType,
      deviceId: _context.deviceId,
      userId: _context.userId,
      baseVersion: current.version,
      baseServerSequence: current.lastServerSequence,
      createdAtLocal: DateTime.now(),
      payload: payload.toJson(),
    );
    await _eventStore.appendAndApply(
      event,
      refs: [
        LocalEventRef.affects(
          refType: ClienteActualizadoPayload.aggregateType,
          refId: current.id,
        ),
      ],
    );
  }

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
