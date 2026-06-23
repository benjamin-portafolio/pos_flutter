import 'handlers/espacio_event_handler.dart';
import 'models/sync_event.dart';

class EventProcessor {
  EventProcessor({required EspacioEventHandler espacioEventHandler})
    : _espacioEventHandler = espacioEventHandler;

  final EspacioEventHandler _espacioEventHandler;

  Future<void> apply(SyncEvent event) {
    switch (event.eventType) {
      case 'espacio_creado':
        return _espacioEventHandler.applyEspacioCreado(event);
      default:
        throw UnsupportedError('Evento no soportado: ${event.eventType}');
    }
  }
}
