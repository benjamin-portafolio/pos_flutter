enum SyncAvailabilityStatus {
  unknown,
  checking,
  available,
  unavailable,
  misconfigured,
}

class SyncAvailabilitySnapshot {
  const SyncAvailabilitySnapshot({
    required this.status,
    this.message,
    this.latestServerSequence,
    this.nextRetryAt,
  });

  const SyncAvailabilitySnapshot.unknown()
    : status = SyncAvailabilityStatus.unknown,
      message = null,
      latestServerSequence = null,
      nextRetryAt = null;

  final SyncAvailabilityStatus status;
  final String? message;
  final int? latestServerSequence;
  final DateTime? nextRetryAt;

  bool get isAvailable => status == SyncAvailabilityStatus.available;
}
