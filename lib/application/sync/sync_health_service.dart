import 'dart:async';

import 'package:http/http.dart' as http;

import 'exceptions/sync_health_exception.dart';
import 'models/sync_health_check.dart';
import 'sync_endpoint_config.dart';

class SyncHealthService {
  SyncHealthService({
    required SyncEndpointConfig endpointConfig,
    http.Client? client,
    Duration timeout = const Duration(seconds: 2),
  }) : _endpointConfig = endpointConfig,
       _client = client ?? http.Client(),
       _timeout = timeout;

  static const supportedApiVersion = SyncHealthCheck.supportedApiVersion;

  final SyncEndpointConfig _endpointConfig;
  final http.Client _client;
  final Duration _timeout;

  Future<SyncHealthCheck> check() async {
    final uri = Uri.parse('${_endpointConfig.baseUrl}/sync/health');

    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_timeout);

      return SyncHealthCheck.fromResponse(
        statusCode: response.statusCode,
        body: response.body,
      );
    } on TimeoutException {
      throw const SyncHealthException(
        'Tiempo de espera agotado comprobando el servidor.',
      );
    } on SyncHealthException {
      rethrow;
    } catch (error) {
      throw SyncHealthException('Error comprobando el servidor: $error');
    }
  }
}
