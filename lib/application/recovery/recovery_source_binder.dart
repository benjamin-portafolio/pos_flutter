abstract interface class RecoverySourceBinder {
  Future<void> bind({
    required Map<String, Object?> prepared,
    required Map<String, Object?> attempt,
    required String enrollmentToken,
  });
}
