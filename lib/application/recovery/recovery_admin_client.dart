import '../config/app_config.dart';

/// Canal administrativo independiente de SQLite y del transporte de sync.
abstract class RecoveryAdminClient {
  Future<Map<String, Object?>> inspect({
    required AppMode mode,
    required String destination,
    required String credential,
  });
  Future<void> execute({
    required AppMode mode,
    required String destination,
    required String credential,
    required Map<String, Object?> snapshot,
    required String action,
    String? requestId,
  });
  void cancel();
}
