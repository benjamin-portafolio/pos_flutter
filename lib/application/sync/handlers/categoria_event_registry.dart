import '../event_handler.dart';
import '../payloads/categoria_actualizada_payload.dart';
import '../payloads/categoria_creada_payload.dart';
import 'categoria_event_handler.dart';

Map<String, EventHandler> categoriaEventHandlers(
  CategoriaEventHandler handler,
) => {
  CategoriaCreadaPayload.eventType: handler.applyCategoriaCreada,
  CategoriaActualizadaPayload.eventType: handler.applyCategoriaActualizada,
};
