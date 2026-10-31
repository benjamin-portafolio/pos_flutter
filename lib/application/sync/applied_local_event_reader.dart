import 'models/sync_event.dart';

/// Lectura durable del resultado dentro de la transacción de la proyección.
abstract interface class AppliedLocalEventReader {
  Future<SyncEvent?> appliedLocalEvent(String operationId);
}
