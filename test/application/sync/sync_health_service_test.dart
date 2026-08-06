import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
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
}
