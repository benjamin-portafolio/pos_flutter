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
    await _eventStore.applySyncedEvents(
      events,
      applyEvent: _eventProcessor.apply,
      acknowledgeEcho: _serverEchoAcknowledger.acknowledge,
      prepareEvent: _remoteEventPreparer?.prepare,
      afterApply: afterApply,
    );
  }
}
