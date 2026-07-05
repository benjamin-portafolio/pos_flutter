import 'models/sync_event.dart';

abstract interface class SyncedEventStore {
  Future<void> applySyncedEvents(
    List<SyncEvent> events, {
    required Future<void> Function(SyncEvent event) applyEvent,
    Future<void> Function()? afterApply,
  });
}
