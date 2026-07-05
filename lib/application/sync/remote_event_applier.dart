import 'event_processor.dart';
import 'models/sync_event.dart';
import 'synced_event_store.dart';

class RemoteEventApplier {
  RemoteEventApplier({
    required SyncedEventStore eventStore,
    required EventProcessor eventProcessor,
  }) : _eventStore = eventStore,
       _eventProcessor = eventProcessor;

  final SyncedEventStore _eventStore;
  final EventProcessor _eventProcessor;

  Future<void> applySyncedEvents(
    List<SyncEvent> events, {
    Future<void> Function()? afterApply,
  }) async {
    await _eventStore.applySyncedEvents(
      events,
      applyEvent: _eventProcessor.apply,
      afterApply: afterApply,
    );
  }
}
