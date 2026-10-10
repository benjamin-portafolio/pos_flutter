import '../models/sync_event.dart';

class VariantTrackingDiscard {
  const VariantTrackingDiscard({
    required this.discardEventId,
    required this.triggerProductEventId,
    required this.event,
    required this.creationEventId,
  });
  final String discardEventId;
  final String triggerProductEventId;
  final SyncEvent event;
  final String creationEventId;
}
