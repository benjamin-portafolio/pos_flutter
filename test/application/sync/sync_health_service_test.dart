import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/models/sync_health_check.dart';
import 'package:pos_flutter/application/sync/sync_health_service.dart';

void main() {
  test('check consulta /sync/health y parsea disponibilidad', () async {
    final service = SyncHealthService(
      endpointConfig: SyncEndpointConfig(
        initialBaseUrl: 'http://localhost:3000',
      ),
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/sync/health');

        return http.Response(
          jsonEncode({
            'status': 'ok',
            'api_version': 1,
            'latest_server_sequence': 12,
            'server_time': '2026-06-09T20:31:05.000Z',
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.check();

    expect(result.isAvailable, isTrue);
    expect(result.latestServerSequence, 12);
  });

  test('check marca como configuracion invalida una version incompatible', () {
    final result = SyncHealthCheck.fromResponse(
      statusCode: 200,
      body: jsonEncode({
        'status': 'ok',
        'api_version': 999,
        'latest_server_sequence': 12,
      }),
    );

    expect(result.isAvailable, isFalse);
    expect(result.isMisconfigured, isTrue);
  });
}
