class SyncPreflightException implements Exception {
  const SyncPreflightException(this.message);

  final String message;

  @override
  String toString() => message;
}
