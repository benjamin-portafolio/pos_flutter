import 'models/sync_event.dart';

abstract interface class LocalEventStore {
  Future<void> appendAndApply(
    SyncEvent event, {
    required List<LocalEventRef> refs,
  });
}

class LocalEventRef {
  const LocalEventRef({
    required this.refType,
    required this.refId,
    required this.relationship,
  });

  const LocalEventRef.affects({required String refType, required String refId})
    : this(refType: refType, refId: refId, relationship: 'affects');

  const LocalEventRef.requiresUnique({
    required String refType,
    required String refId,
  }) : this(refType: refType, refId: refId, relationship: 'requires_unique');

  final String refType;
  final String refId;
  final String relationship;
}
