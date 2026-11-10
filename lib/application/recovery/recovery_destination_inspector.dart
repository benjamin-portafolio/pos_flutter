import '../config/app_config.dart';

/// Inspección dedicada y de solo lectura; nunca reserva una recuperación.
abstract interface class RecoveryDestinationInspector {
  void cancel();
  Future<Map<String, Object?>> inspect({
    required AppMode mode,
    required Uri destination,
    required String token,
  });
}
