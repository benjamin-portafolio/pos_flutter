import 'models/sync_event.dart';
import 'payloads/cliente_actualizado_payload.dart';
import 'projections/cliente_projection.dart';
import 'projections/cliente_projection_store.dart';

class ClienteConflictProjectionRestorer {
  ClienteConflictProjectionRestorer(this._store);
  final ClienteProjectionStore _store;
  Future<void> restore(SyncEvent event) async {
    final payload = ClienteActualizadoPayload.fromJson(event.payload);
    final current = await _store.findById(event.aggregateId);
    if (current == null || current.lastEventId != event.eventId) return;
    await _store.insert(
      ClienteProjection(
        id: current.id,
        nombre: payload.before.nombre,
        telefono: payload.before.telefono,
        active: current.active,
        version: event.baseVersion!,
        createdEventId: current.createdEventId,
        lastEventId: payload.baseEventId,
        lastServerSequence: current.lastServerSequence,
      ),
    );
  }
}
