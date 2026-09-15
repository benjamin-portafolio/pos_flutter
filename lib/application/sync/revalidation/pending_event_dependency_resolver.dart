import '../synced_event_history.dart';
import 'resolved_event_base.dart';

class PendingEventDependencyResolver {
  const PendingEventDependencyResolver(this._syncedEventHistory);

  final SyncedEventHistory _syncedEventHistory;

  Future<bool> hasFailed(String eventId) async {
    final dependency = await _syncedEventHistory.eventById(eventId);
    return dependency?.deliveryStatus == 'conflict' ||
        dependency?.deliveryStatus == 'rejected';
  }

  Future<ResolvedEventBase> resolveBase({
    required String baseEventId,
    required int? fallbackServerSequence,
  }) async {
    final baseEvent = await _syncedEventHistory.eventById(baseEventId);
    if (baseEvent == null) {
      return ResolvedEventBase(serverSequence: fallbackServerSequence);
    }

    if (baseEvent.deliveryStatus != 'delivered' ||
        baseEvent.serverSequence == null) {
      return const ResolvedEventBase(waitsForLocalDependency: true);
    }

    final officialSequence = baseEvent.serverSequence!;
    final effectiveSequence =
        fallbackServerSequence == null ||
            officialSequence > fallbackServerSequence
        ? officialSequence
        : fallbackServerSequence;
    return ResolvedEventBase(serverSequence: effectiveSequence);
  }
}
