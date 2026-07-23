import 'categoria_conflict_projection_restorer.dart';
import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/espacio_creado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/espacio_projection_store.dart';

class SyncConflictProjectionCleaner {
  SyncConflictProjectionCleaner({
    required EspacioProjectionStore espacioProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
    required CategoriaConflictProjectionRestorer
    categoriaConflictProjectionRestorer,
  }) : _espacioProjectionStore = espacioProjectionStore,
       _categoriaProjectionStore = categoriaProjectionStore,
       _categoriaConflictProjectionRestorer =
           categoriaConflictProjectionRestorer;

  final EspacioProjectionStore _espacioProjectionStore;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final CategoriaConflictProjectionRestorer
  _categoriaConflictProjectionRestorer;

  Future<void> hideConflictProjection(SyncEvent event) async {
    if (event.eventType == EspacioCreadoPayload.eventType) {
      await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType == CategoriaCreadaPayload.eventType) {
      await _categoriaProjectionStore.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType == CategoriaActualizadaPayload.eventType) {
      await _categoriaConflictProjectionRestorer.restore(event);
    }
  }
}
