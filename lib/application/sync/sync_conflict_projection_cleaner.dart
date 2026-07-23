import 'models/sync_event.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/espacio_creado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/espacio_projection_store.dart';

class SyncConflictProjectionCleaner {
  SyncConflictProjectionCleaner({
    required EspacioProjectionStore espacioProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
  }) : _espacioProjectionStore = espacioProjectionStore,
       _categoriaProjectionStore = categoriaProjectionStore;

  final EspacioProjectionStore _espacioProjectionStore;
  final CategoriaProjectionStore _categoriaProjectionStore;

  Future<void> hideConflictProjection(SyncEvent event) async {
    if (event.eventType == EspacioCreadoPayload.eventType) {
      await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType == CategoriaCreadaPayload.eventType) {
      await _categoriaProjectionStore.deleteCreatedByEvent(event.eventId);
    }
  }
}
