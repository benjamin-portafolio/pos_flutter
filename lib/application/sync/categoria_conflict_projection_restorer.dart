import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'projections/categoria_projection_store.dart';

class CategoriaConflictProjectionRestorer {
  CategoriaConflictProjectionRestorer(this._categoriaProjectionStore);

  final CategoriaProjectionStore _categoriaProjectionStore;

  Future<void> restore(
    SyncEvent event, {
    Set<String> officialChangedFields = const {},
  }) async {
    final payload = CategoriaActualizadaPayload.fromJson(event.payload);
    final existing = await _categoriaProjectionStore.findById(
      event.aggregateId,
    );
    if (existing == null) return;

    final restoreName =
        payload.cambiaNombre &&
        !officialChangedFields.contains(
          CategoriaActualizadaPayload.nameField,
        ) &&
        existing.nombre == payload.nombreNuevo;
    final restoreColor =
        payload.cambiaColor &&
        !officialChangedFields.contains(
          CategoriaActualizadaPayload.colorKeyField,
        ) &&
        existing.color == payload.colorNuevo;
    final hasNewerOfficialState =
        existing.lastServerSequence != null &&
        (event.baseServerSequence == null ||
            existing.lastServerSequence! > event.baseServerSequence!);

    await _categoriaProjectionStore.update(
      CategoriaProjection(
        id: existing.id,
        nombre: restoreName ? payload.nombreAnterior! : existing.nombre,
        color: restoreColor ? payload.colorAnterior! : existing.color,
        orden: existing.orden,
        active: existing.active,
        version: hasNewerOfficialState
            ? existing.version
            : event.baseVersion ?? existing.version,
        createdEventId: existing.createdEventId,
        lastEventId: existing.lastEventId == event.eventId
            ? payload.baseEventId
            : existing.lastEventId,
        lastServerSequence: existing.lastServerSequence,
      ),
    );
  }
}
