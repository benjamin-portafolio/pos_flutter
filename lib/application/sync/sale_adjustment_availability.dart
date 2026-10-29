import '../config/app_config.dart';
import '../config/app_config_controller.dart';
import 'exceptions/sync_health_exception.dart';
import 'sync_capability_store.dart';
import 'sync_endpoint_config.dart';
import 'sync_health_service.dart';

/// Captures use the last successful negotiation for the selected server.
/// Network failure preserves that knowledge; an incompatible response revokes it.
class SaleAdjustmentAvailability {
  SaleAdjustmentAvailability({
    required this.config,
    required this.endpoint,
    required this.store,
    required this.health,
  });
  final AppConfigController config;
  final SyncEndpointConfig endpoint;
  final SyncCapabilityStore store;
  final SyncHealthService Function() health;
  Future<void> requireCompatible({bool refresh = false}) async {
    if (config.mode == AppMode.standalone) return;
    final server = endpoint.baseUrl;
    if (refresh) {
      try {
        await health().check();
      } on SyncHealthException {
        // Offline is allowed only with a compatible observation already saved.
      }
    }
    final capabilities = await store.read(server);
    if (endpoint.baseUrl != server || capabilities == null) {
      throw StateError(
        'Conecta con este servidor para verificar compatibilidad antes de registrar ajustes.',
      );
    }
    if (!capabilities.contains('sale_adjustments_v1') ||
        !capabilities.contains('sale_reconciliations_v1')) {
      throw StateError(
        'Servidor incompatible: requiere sale_adjustments_v1 y sale_reconciliations_v1.',
      );
    }
  }
}
