import 'event_handler.dart';
import 'models/sync_event.dart';

class EventProcessor {
  EventProcessor({required Map<String, EventHandler> handlers})
    : _handlers = Map.unmodifiable(handlers);

  final Map<String, EventHandler> _handlers;

  Future<void> apply(SyncEvent event) {
    final handler = _handlers[event.eventType];
    if (handler == null) {
      throw UnsupportedError('Evento no soportado: ${event.eventType}');
    }

    return handler(event);
  }
}
