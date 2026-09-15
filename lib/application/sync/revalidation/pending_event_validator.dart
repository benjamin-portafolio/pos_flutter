import '../models/sync_event.dart';
import 'pending_conflict.dart';

abstract interface class PendingEventValidator {
  Future<PendingConflict?> validate(
    SyncEvent event,
    Set<String> conflictedEventIds,
  );

  Future<void> restore(SyncEvent event, PendingConflict conflict);
}
