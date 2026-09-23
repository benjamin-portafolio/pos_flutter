import '../models/sync_event.dart';
import '../payloads/cliente_actualizado_payload.dart';
import '../payloads/cliente_creado_payload.dart';
import '../projections/cliente_projection.dart';
import '../projections/cliente_projection_store.dart';

class ClienteEventHandler {
  ClienteEventHandler(this._store);
  final ClienteProjectionStore _store;

  Future<void> applyUpdate(SyncEvent event) async {
    if (event.aggregateType != ClienteActualizadoPayload.aggregateType ||
        event.baseVersion == null ||
        event.baseVersion! < 1) {
      throw const FormatException('Base de cliente inválida.');
    }
    final payload = ClienteActualizadoPayload.fromJson(event.payload);
    final current = await _store.findById(event.aggregateId);
    if (current?.lastEventId == event.eventId) {
      if (event.serverSequence != null) {
        await _store.advanceServerSequence(
          event.aggregateId,
          event.serverSequence!,
        );
      }
      return;
    }
    if (current == null ||
        !current.active ||
        current.lastEventId != payload.baseEventId ||
        current.version != event.baseVersion ||
        current.nombre != payload.before.nombre ||
        current.telefono != payload.before.telefono) {
      throw StateError('El cliente cambió desde que se abrió la edición.');
    }
    await _store.insert(
      ClienteProjection(
        id: current.id,
        nombre: payload.after.nombre,
        telefono: payload.after.telefono,
        active: current.active,
        version: current.version + 1,
        createdEventId: current.createdEventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence ?? current.lastServerSequence,
      ),
    );
  }

  Future<void> apply(SyncEvent event) async {
    if (event.aggregateType != ClienteCreadoPayload.aggregateType ||
        event.baseVersion != 1 ||
        event.baseServerSequence != null) {
      throw const FormatException(
        'El alta del cliente requiere versión 1 y ninguna base oficial.',
      );
    }
    final payload = ClienteCreadoPayload.fromJson(event.payload);
    final existing = await _store.findById(event.aggregateId);
    if (existing != null) {
      if (existing.createdEventId == event.eventId) {
        if (event.serverSequence != null) {
          await _store.advanceServerSequence(
            event.aggregateId,
            event.serverSequence!,
          );
        }
        return;
      }
      if (event.serverSequence == null ||
          existing.lastServerSequence != null ||
          existing.createdEventId == null) {
        throw StateError('Ya existe un cliente con id ${event.aggregateId}.');
      }
      // El estado oficial reemplaza el alta optimista; la revalidación marca el conflicto.
      await _store.deleteCreatedByEvent(existing.createdEventId!);
    }
    await _store.insert(
      ClienteProjection(
        id: event.aggregateId,
        nombre: payload.nombre,
        telefono: payload.telefono,
        active: true,
        version: 1,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence,
      ),
    );
  }
}
