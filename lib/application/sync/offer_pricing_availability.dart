import '../config/app_config.dart';
import '../config/app_config_controller.dart';
import 'sync_capability_store.dart';
import 'sync_endpoint_config.dart';

/// Permite captura offline solo tras acreditar el receptor seleccionado.
/// Standalone no consulta capacidades ni inicia servicios de red.
class OfferPricingAvailability {
  const OfferPricingAvailability({
    required this.config,
    required this.endpoint,
    required this.store,
  });
  final AppConfigController config;
  final SyncEndpointConfig endpoint;
  final SyncCapabilityStore store;

  Future<void> requireCompatible() async {
    if (config.mode == AppMode.standalone) return;
    final server = endpoint.baseUrl;
    final capabilities = await store.read(server);
    if (server != endpoint.baseUrl ||
        capabilities == null ||
        !capabilities.contains('offer_pricing_v2')) {
      throw StateError(
        'Verifica la conexión y que el servidor esté actualizado para usar precios de oferta.',
      );
    }
  }
}
