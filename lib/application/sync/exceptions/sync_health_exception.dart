class SyncHealthException implements Exception {
  const SyncHealthException(this.message);

  final String message;

  @override
  String toString() => message;
}
