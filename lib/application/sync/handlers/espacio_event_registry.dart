import '../event_handler.dart';
import 'espacio_event_handler.dart';

Map<String, EventHandler> espacioEventHandlers(EspacioEventHandler handler) => {
  'espacio_creado': handler.applyEspacioCreado,
};
