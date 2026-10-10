import 'payloads/recurso_inventario_descartado_payload.dart';
import 'event_processor.dart';
import 'models/sync_event.dart';
import 'server_echo_acknowledger.dart';
import 'remote_event_preparer.dart';
import 'synced_event_store.dart';

class RemoteEventApplier {
  RemoteEventApplier({
    required SyncedEventStore eventStore,
    required EventProcessor eventProcessor,
    required ServerEchoAcknowledger serverEchoAcknowledger,
    RemoteEventPreparer? remoteEventPreparer,
  }) : _eventStore = eventStore,
       _eventProcessor = eventProcessor,
       _serverEchoAcknowledger = serverEchoAcknowledger,
       _remoteEventPreparer = remoteEventPreparer;

  final SyncedEventStore _eventStore;
  final EventProcessor _eventProcessor;
  final ServerEchoAcknowledger _serverEchoAcknowledger;
  final RemoteEventPreparer? _remoteEventPreparer;

  Future<void> applySyncedEvents(
    List<SyncEvent> events, {
    Future<void> Function()? afterApply,
  }) async {
    for (final event in events) {
      if (!_eventProcessor.supports(event.eventType)) {
        throw UnsupportedError('Evento no soportado: ${event.eventType}');
      }
    }
    if (events.any(
      (e) => e.eventType == RecursoInventarioDescartadoPayload.eventType,
    )) {
      throw StateError(
        'El descarte standalone no se acepta por sincronización remota.',
      );
    }
    await _eventStore.applySyncedEvents(
      events,
      applyEvent: _eventProcessor.apply,
      acknowledgeEcho: _serverEchoAcknowledger.acknowledge,
      prepareEvent: _remoteEventPreparer?.prepare,
      afterApply: afterApply,
    );
  }
}
