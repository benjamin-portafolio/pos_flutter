import '../event_handler.dart';
import '../payloads/espacio_creado_payload.dart';
import 'espacio_event_handler.dart';

Map<String, EventHandler> espacioEventHandlers(EspacioEventHandler handler) => {
  EspacioCreadoPayload.eventType: handler.applyEspacioCreado,
};
