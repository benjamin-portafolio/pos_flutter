import 'categoria_conflict_projection_restorer.dart';
import 'categoria_movida_conflict_projection_restorer.dart';
import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/categoria_movida_payload.dart';
import 'payloads/espacio_creado_payload.dart';
import 'payloads/producto_creado_payload.dart';
import 'projections/categoria_projection_store.dart';
import 'projections/espacio_projection_store.dart';
import 'projections/producto_projection_store.dart';

class SyncConflictProjectionCleaner {
  SyncConflictProjectionCleaner({
    required EspacioProjectionStore espacioProjectionStore,
    required CategoriaProjectionStore categoriaProjectionStore,
    ProductoProjectionStore? productoProjectionStore,
    required CategoriaConflictProjectionRestorer
    categoriaConflictProjectionRestorer,
    required CategoriaMovidaConflictProjectionRestorer
    categoriaMovidaConflictProjectionRestorer,
  }) : _espacioProjectionStore = espacioProjectionStore,
       _categoriaProjectionStore = categoriaProjectionStore,
       _productoProjectionStore = productoProjectionStore,
       _categoriaConflictProjectionRestorer =
           categoriaConflictProjectionRestorer,
       _categoriaMovidaConflictProjectionRestorer =
           categoriaMovidaConflictProjectionRestorer;

  final EspacioProjectionStore _espacioProjectionStore;
  final CategoriaProjectionStore _categoriaProjectionStore;
  final ProductoProjectionStore? _productoProjectionStore;
  final CategoriaConflictProjectionRestorer
  _categoriaConflictProjectionRestorer;
  final CategoriaMovidaConflictProjectionRestorer
  _categoriaMovidaConflictProjectionRestorer;

  Future<void> hideConflictProjection(SyncEvent event) async {
    if (event.eventType == EspacioCreadoPayload.eventType) {
      await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType == CategoriaCreadaPayload.eventType) {
      await _categoriaProjectionStore.deleteCreatedByEvent(event.eventId);
    } else if (event.eventType == CategoriaActualizadaPayload.eventType) {
      await _categoriaConflictProjectionRestorer.restore(event);
    } else if (event.eventType == CategoriaMovidaPayload.eventType) {
      await _categoriaMovidaConflictProjectionRestorer.restore(event);
    } else if (event.eventType == ProductoCreadoPayload.eventType) {
      await _productoProjectionStore?.deleteCreatedByEvent(event.eventId);
    }
  }
}
