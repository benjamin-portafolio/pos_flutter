import 'models/sync_event.dart';
import 'payloads/categoria_actualizada_payload.dart';
import 'payloads/categoria_creada_payload.dart';
import 'payloads/categoria_movida_payload.dart';
import 'projections/categoria_projection_store.dart';

class ServerEchoAcknowledger {
  ServerEchoAcknowledger({
    required CategoriaProjectionStore categoriaProjectionStore,
  }) : _categoriaProjectionStore = categoriaProjectionStore;

  final CategoriaProjectionStore _categoriaProjectionStore;

  Future<void> acknowledge(SyncEvent event) async {
    final serverSequence = event.serverSequence;
    if (serverSequence == null) return;

    switch (event.eventType) {
      case CategoriaCreadaPayload.eventType:
      case CategoriaActualizadaPayload.eventType:
        await _categoriaProjectionStore.advanceLastServerSequence(
          event.aggregateId,
          serverSequence,
        );
        return;
      case CategoriaMovidaPayload.eventType:
        final payload = CategoriaMovidaPayload.fromJson(event.payload);
        await _categoriaProjectionStore.advanceLastServerSequence(
          event.aggregateId,
          serverSequence,
        );
        await _categoriaProjectionStore.advanceLastServerSequence(
          payload.categoriaDesplazadaId,
          serverSequence,
        );
        return;
    }
  }
}
