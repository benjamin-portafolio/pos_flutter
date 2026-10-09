import 'event_handler.dart';
import 'models/sync_event.dart';

class EventProcessor {
  EventProcessor({required Map<String, EventHandler> handlers})
    : _handlers = Map.unmodifiable(handlers);

  final Map<String, EventHandler> _handlers;

  bool supports(String eventType) => _handlers.containsKey(eventType);

  Future<void> apply(SyncEvent event) {
    final handler = _handlers[event.eventType];
    if (handler == null) {
      throw UnsupportedError('Evento no soportado: ${event.eventType}');
    }

    return handler(event);
  }
}
