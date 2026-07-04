class SyncPushException implements Exception {
  const SyncPushException(this.message);

  final String message;

  @override
  String toString() => message;
}
