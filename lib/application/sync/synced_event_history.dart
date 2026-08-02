import 'models/sync_event.dart';

abstract interface class SyncedEventHistory {
  Future<SyncEvent?> eventById(String eventId);

  Future<List<SyncEvent>> eventsForAggregateAfter({
    required String aggregateType,
    required String aggregateId,
    required int serverSequence,
  });

  Future<List<SyncEvent>> eventsByTypeAfter({
    required String eventType,
    required int serverSequence,
  });
}
