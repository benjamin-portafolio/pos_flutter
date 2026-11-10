import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/local/recovery/http_recovery_destination_inspector.dart';

const serverId = '80000000-0000-4000-8000-000000000001';
const generation = '80000000-0000-4000-8000-000000000002';
final token = 'a' * 64;
Map<String, Object?> health() => {
  'recovery_protocol': 1,
  'sync_protocol': 2,
  'server_instance_id': serverId,
  'generation_id': generation,
  'latest_server_sequence': 0,
};
Map<String, Object?> eligibility() => {
  'protocol_version': 1,
  'server_instance_id': serverId,
  'generation_id': generation,
  'eligible': false,
  'reasons': ['destination_not_empty'],
  'counts': {'events': 1},
  'schema_fingerprint': 'b' * 64,
  'commercial_recovery_complete': false,
};
void main() {
  test('standalone no construye cliente ni hace health', () async {
    var calls = 0;
    final inspector = HttpRecoveryDestinationInspector(
      clientFactory: () {
        calls++;
        throw StateError('No red');
      },
    );
    await expectLater(
      inspector.inspect(
        mode: AppMode.standalone,
        destination: Uri.parse('https://destination.test'),
        token: token,
      ),
      throwsStateError,
    );
    expect(calls, 0);
  });
  for (final input in [
    'http://192.168.1.10:3000',
    'https://user:secret@destination.test',
    'https://destination.test/private',
    'https://destination.test?token=secret',
    'ftp://destination.test',
  ]) {
    test('rechaza URL $input antes de red', () async {
      final inspector = HttpRecoveryDestinationInspector(
        clientFactory: () => throw StateError('No red'),
      );
      await expectLater(
        inspector.inspect(
          mode: AppMode.serverSync,
          destination: Uri.parse(input),
          token: token,
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'health 0 no sustituye elegibilidad y secreto solo va a eligibility',
    () async {
      final seen = <http.Request>[];
      final inspector = HttpRecoveryDestinationInspector(
        clientFactory: () => MockClient((request) async {
          seen.add(request);
          expect(request.followRedirects, false);
          if (request.url.path == '/sync/health') {
            expect(request.headers.containsKey('Authorization'), false);
            return http.Response(jsonEncode(health()), 200);
          }
          expect(request.headers['Authorization'], 'Bearer $token');
          expect(request.headers['X-POS-Server'], serverId);
          expect(request.headers['X-POS-Generation'], generation);
          return http.Response(jsonEncode(eligibility()), 200);
        }),
      );
      final result = await inspector.inspect(
        mode: AppMode.serverSync,
        destination: Uri.parse('https://destination.test'),
        token: token,
      );
      expect(result['eligible'], false);
      expect(result['commercial_recovery_complete'], false);
      expect(seen.map((r) => '${r.method} ${r.url.path}'), [
        'GET /sync/health',
        'GET /recovery/eligibility',
      ]);
    },
  );
  test('incompatible no recibe credencial', () async {
    var calls = 0;
    final inspector = HttpRecoveryDestinationInspector(
      clientFactory: () => MockClient((r) async {
        calls++;
        expect(r.headers.containsKey('Authorization'), false);
        return http.Response('{"latest_server_sequence":0}', 200);
      }),
    );
    await expectLater(
      inspector.inspect(
        mode: AppMode.serverSync,
        destination: Uri.parse('https://destination.test'),
        token: token,
      ),
      throwsFormatException,
    );
    expect(calls, 1);
  });
  for (final status in [302, 401, 403]) {
    test('rechaza HTTP $status sin reserva ni fallback', () async {
      var calls = 0;
      final inspector = HttpRecoveryDestinationInspector(
        clientFactory: () => MockClient((r) async {
          calls++;
          return calls == 1
              ? http.Response(jsonEncode(health()), 200)
              : http.Response(
                  '{}',
                  status,
                  headers: {'location': 'https://other.test'},
                );
        }),
      );
      await expectLater(
        inspector.inspect(
          mode: AppMode.serverSync,
          destination: Uri.parse('https://destination.test'),
          token: token,
        ),
        throwsFormatException,
      );
      expect(calls, 2);
    });
  }
  test('cambio de generación entre consultas bloquea el informe', () async {
    var calls = 0;
    final inspector = HttpRecoveryDestinationInspector(
      clientFactory: () => MockClient((r) async {
        calls++;
        return http.Response(
          jsonEncode(
            calls == 1
                ? health()
                : (eligibility()..['generation_id'] = serverId),
          ),
          200,
        );
      }),
    );
    await expectLater(
      inspector.inspect(
        mode: AppMode.serverSync,
        destination: Uri.parse('https://destination.test'),
        token: token,
      ),
      throwsFormatException,
    );
  });
  test(
    'loopback HTTP real solo recibe las dos lecturas; repetir no crea sesión',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String>[];
      server.listen((request) async {
        seen.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path == '/sync/health' ? health() : eligibility(),
          ),
        );
        await request.response.close();
      });
      try {
        final inspector = HttpRecoveryDestinationInspector();
        for (var i = 0; i < 2; i++) {
          final report = await inspector.inspect(
            mode: AppMode.serverSync,
            destination: Uri.parse('http://127.0.0.1:${server.port}'),
            token: token,
          );
          expect(report['eligible'], false);
        }
        expect(seen, [
          'GET /sync/health',
          'GET /recovery/eligibility',
          'GET /sync/health',
          'GET /recovery/eligibility',
        ]);
      } finally {
        await server.close(force: true);
      }
    },
  );
}
