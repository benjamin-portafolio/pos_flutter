import '../models/sync_event.dart';
import '../payloads/cliente_creado_payload.dart';
import '../projections/cliente_projection.dart';
import '../projections/cliente_projection_store.dart';

class ClienteEventHandler {
  ClienteEventHandler(this._store);
  final ClienteProjectionStore _store;

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
            event.eventId,
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
