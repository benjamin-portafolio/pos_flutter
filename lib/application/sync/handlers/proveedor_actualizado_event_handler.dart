import '../models/sync_event.dart';
import '../payloads/proveedor_actualizado_payload.dart';
import '../payloads/supplier_json.dart';
import '../projections/proveedor_projection.dart';
import '../projections/proveedor_projection_store.dart';

class ProveedorActualizadoEventHandler {
  ProveedorActualizadoEventHandler(this._store);
  final ProveedorProjectionStore _store;

  Future<void> apply(SyncEvent event) async {
    if (event.aggregateType != ProveedorActualizadoPayload.aggregateType ||
        event.eventType != ProveedorActualizadoPayload.eventType ||
        event.baseVersion == null ||
        event.baseVersion! < 1) {
      throw const FormatException('Base de proveedor inválida.');
    }
    final id = SupplierJson.uuid(event.aggregateId, 'aggregate_id');
    SupplierJson.uuid(event.eventId, 'event_id');
    final payload = ProveedorActualizadoPayload.fromJson(event.payload);
    final current = await _store.findById(id);
    if (current?.lastEventId == event.eventId) return;
    if (current == null ||
        !current.active ||
        current.lastEventId != payload.baseEventId ||
        current.version != event.baseVersion ||
        (event.baseServerSequence != null &&
            current.lastServerSequence != event.baseServerSequence) ||
        !ProveedorActualizadoPayload.sameState(current.state, payload.before)) {
      throw StateError('El proveedor cambió desde que se abrió la edición.');
    }
    await _store.save(
      ProveedorProjection(
        id: current.id,
        name: payload.after.name,
        phone: payload.after.phone,
        notes: payload.after.notes,
        active: current.active,
        version: current.version + 1,
        createdEventId: current.createdEventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence ?? current.lastServerSequence,
      ),
    );
  }
}
