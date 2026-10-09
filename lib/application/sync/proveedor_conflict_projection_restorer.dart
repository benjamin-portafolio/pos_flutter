import 'models/sync_event.dart';
import 'payloads/proveedor_actualizado_payload.dart';
import 'projections/proveedor_projection.dart';
import 'projections/proveedor_projection_store.dart';

class ProveedorConflictProjectionRestorer {
  ProveedorConflictProjectionRestorer(this._store);
  final ProveedorProjectionStore _store;

  Future<void> restore(SyncEvent event) async {
    final payload = ProveedorActualizadoPayload.fromJson(event.payload);
    final current = await _store.findById(event.aggregateId);
    if (current == null || current.lastEventId != event.eventId) return;
    await _store.save(
      ProveedorProjection(
        id: current.id,
        name: payload.before.name,
        phone: payload.before.phone,
        notes: payload.before.notes,
        active: current.active,
        version: event.baseVersion!,
        createdEventId: current.createdEventId,
        lastEventId: payload.baseEventId,
        lastServerSequence: current.lastServerSequence,
      ),
    );
  }
}
