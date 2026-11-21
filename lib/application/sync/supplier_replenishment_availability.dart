import '../config/app_config.dart';
import '../config/app_config_controller.dart';
import 'sync_capability_store.dart';
import 'sync_endpoint_config.dart';

/// Permite captura offline solo tras acreditar el receptor seleccionado.
/// Standalone no consulta capacidades ni inicia servicios de red.
class SupplierReplenishmentAvailability {
  const SupplierReplenishmentAvailability({
    required this.config,
    required this.endpoint,
    required this.store,
  });
  final AppConfigController config;
  final SyncEndpointConfig endpoint;
  final SyncCapabilityStore store;

  Future<void> requireCompatible({
    String capability = 'supplier_replenishment_v1',
  }) async {
    if (config.mode == AppMode.standalone) return;
    final server = endpoint.baseUrl;
    final capabilities = await store.read(server);
    if (server != endpoint.baseUrl ||
        capabilities == null ||
        !capabilities.contains(capability)) {
      throw StateError(
        'Verifica la conexión y que el servidor esté actualizado para configurar reposición.',
      );
    }
  }
}
