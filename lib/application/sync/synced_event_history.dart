import 'models/sync_event.dart';

abstract interface class SyncedEventHistory {
  Future<List<SyncEvent>> eventsForAggregateAfter({
    required String aggregateType,
    required String aggregateId,
    required int serverSequence,
  });
}
