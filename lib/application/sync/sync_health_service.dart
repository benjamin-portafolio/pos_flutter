import 'dart:async';

import 'package:http/http.dart' as http;

import 'exceptions/sync_health_exception.dart';
import 'models/sync_health_check.dart';
import 'sync_endpoint_config.dart';
import 'sync_capability_store.dart';

class SyncHealthService {
  SyncHealthService({
    required SyncEndpointConfig endpointConfig,
    http.Client? client,
    SyncCapabilityStore? capabilityStore,
    Duration timeout = const Duration(seconds: 2),
  }) : _capabilityStore = capabilityStore,
       _endpointConfig = endpointConfig,
       _client = client ?? http.Client(),
       _timeout = timeout;

  final SyncCapabilityStore? _capabilityStore;
  final SyncEndpointConfig _endpointConfig;
  final http.Client _client;
  final Duration _timeout;

  Future<SyncHealthCheck> check() async {
    final endpoint = _endpointConfig.baseUrl;
    final uri = Uri.parse('$endpoint/sync/health');

    late http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);
    } on TimeoutException {
      throw const SyncHealthException(
        'Tiempo de espera agotado comprobando el servidor.',
      );
    } on SyncHealthException {
      rethrow;
    } catch (error) {
      throw SyncHealthException('Error comprobando el servidor: $error');
    }
    final result = SyncHealthCheck.fromResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
    if (result.isAvailable || result.isMisconfigured) {
      await _capabilityStore?.write(
        endpoint,
        result.isAvailable ? result.capabilities : const [],
      );
    }
    return result;
  }
}
