class SyncConflictReportException implements Exception {
  const SyncConflictReportException(this.message);

  final String message;

  @override
  String toString() => 'SyncConflictReportException: $message';
}
