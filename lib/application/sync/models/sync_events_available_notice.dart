class SyncEventsAvailableNotice {
  const SyncEventsAvailableNotice({
    required this.latestServerSequence,
    required this.eventTypes,
    required this.sourceDeviceId,
  });

  final int latestServerSequence;
  final List<String> eventTypes;
  final String? sourceDeviceId;
}
