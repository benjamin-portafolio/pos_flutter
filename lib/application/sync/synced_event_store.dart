import 'models/sync_event.dart';

abstract interface class SyncedEventStore {
  Future<void> applySyncedEvents(
    List<SyncEvent> events, {
    required Future<void> Function(SyncEvent event) applyEvent,
    required Future<void> Function(SyncEvent event) acknowledgeEcho,
    Future<void> Function(SyncEvent event)? prepareEvent,
    Future<void> Function()? afterApply,
  });
}
