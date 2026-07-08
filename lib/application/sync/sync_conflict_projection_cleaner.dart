import 'models/sync_event.dart';
import 'projections/espacio_projection_store.dart';

class SyncConflictProjectionCleaner {
  SyncConflictProjectionCleaner({
    required EspacioProjectionStore espacioProjectionStore,
  }) : _espacioProjectionStore = espacioProjectionStore;

  final EspacioProjectionStore _espacioProjectionStore;

  Future<void> hideConflictProjection(SyncEvent event) async {
    if (event.eventType == 'espacio_creado') {
      await _espacioProjectionStore.deleteCreatedByEvent(event.eventId);
    }
  }
}
