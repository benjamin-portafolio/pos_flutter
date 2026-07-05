import 'models/sync_event.dart';

abstract interface class SyncPersistence {
  Future<List<SyncEvent>> pendingEvents();

  Stream<List<SyncEvent>> watchPendingEvents();

  Future<void> updateEventSyncStatus(
    String eventId,
    String status, {
    int? serverSequence,
    DateTime? serverTime,
  });

  Future<List<StoredEventRef>> refsForEvents(List<String> eventIds);

  Future<void> markRefsSynced(String eventId, int serverSequence);

  Future<int> lastFullPullServerSequence();

  Future<int> lastPreflightServerSequence();

  Future<void> updateLastFullPullServerSequence(
    int serverSequence, {
    DateTime? pulledAt,
  });

  Future<void> updateLastPreflightServerSequence(
    int serverSequence, {
    DateTime? preflightAt,
  });
}

class StoredEventRef {
  const StoredEventRef({
    required this.eventId,
    required this.refType,
    required this.refId,
    required this.relationship,
    required this.source,
    this.serverSequence,
  });

  final String eventId;
  final String refType;
  final String refId;
  final String relationship;
  final String source;
  final int? serverSequence;
}
