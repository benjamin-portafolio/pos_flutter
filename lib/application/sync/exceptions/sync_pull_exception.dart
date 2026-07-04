class SyncPullException implements Exception {
  const SyncPullException(this.message);

  final String message;

  @override
  String toString() => message;
}
