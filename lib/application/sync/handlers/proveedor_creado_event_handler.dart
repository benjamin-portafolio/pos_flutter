import '../models/sync_event.dart';
import '../payloads/proveedor_creado_payload.dart';
import '../payloads/supplier_json.dart';
import '../projections/proveedor_projection.dart';
import '../projections/proveedor_projection_store.dart';

class ProveedorCreadoEventHandler {
  ProveedorCreadoEventHandler(this._store);
  final ProveedorProjectionStore _store;

  Future<void> apply(SyncEvent event) async {
    if (event.aggregateType != ProveedorCreadoPayload.aggregateType ||
        event.eventType != ProveedorCreadoPayload.eventType ||
        event.baseVersion != 1 ||
        event.baseServerSequence != null) {
      throw const FormatException(
        'El alta del proveedor requiere versión 1 y ninguna base oficial.',
      );
    }
    final id = SupplierJson.uuid(event.aggregateId, 'aggregate_id');
    SupplierJson.uuid(event.eventId, 'event_id');
    final payload = ProveedorCreadoPayload.fromJson(event.payload);
    final existing = await _store.findById(id);
    if (existing != null) {
      if (existing.createdEventId == event.eventId) return;
      throw StateError('Ya existe un proveedor con id $id.');
    }
    await _store.save(
      ProveedorProjection(
        id: id,
        name: payload.name,
        phone: payload.phone,
        notes: payload.notes,
        active: true,
        version: 1,
        createdEventId: event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence,
      ),
    );
  }
}
