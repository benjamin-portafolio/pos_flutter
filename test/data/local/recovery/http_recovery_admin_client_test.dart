import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/local/recovery/http_recovery_admin_client.dart';

const server = '11111111-1111-4111-8111-111111111111';
const generation = '22222222-2222-4222-8222-222222222222';
final credential = 'a' * 64;
Map<String, Object?> snapshot() => {
  'protocol_version': 1,
  'server_instance_id': server,
  'generation_id': generation,
  'revision': 3,
  'recovery_enabled': false,
  'requests': [],
  'eligibility': {'eligible': true, 'reasons': []},
};

void main() {
  test(
    'enrollment actions use authenticated destination and expected revision without a recovery request',
    () async {
      for (final action in ['enrollment-enable', 'enrollment-disable']) {
        final client = HttpRecoveryAdminClient(
          clientFactory: () => MockClient((r) async {
            expect(r.url.path, '/recovery-admin/actions');
            expect(r.headers['Authorization'], 'Bearer $credential');
            expect(r.headers['X-POS-Generation'], generation);
            expect(jsonDecode(r.body), {
              'action': action,
              'expected_revision': 3,
            });
            return http.Response(
              jsonEncode({
                'protocol_version': 1,
                'server_instance_id': server,
                'generation_id': generation,
                'revision': 4,
                'action': action,
              }),
              200,
            );
          }),
        );
        await client.execute(
          mode: AppMode.serverSync,
          destination: 'https://pos.example',
          credential: credential,
          snapshot: snapshot(),
          action: action,
        );
      }
    },
  );

  test(
    'standalone and insecure remote destinations never create a network client',
    () async {
      var clients = 0;
      final client = HttpRecoveryAdminClient(
        clientFactory: () {
          clients++;
          return MockClient((_) async => http.Response('{}', 200));
        },
      );
      await expectLater(
        client.inspect(
          mode: AppMode.standalone,
          destination: 'https://pos.example',
          credential: credential,
        ),
        throwsStateError,
      );
      await expectLater(
        client.inspect(
          mode: AppMode.serverSync,
          destination: 'http://public.example',
          credential: credential,
        ),
        throwsFormatException,
      );
      expect(clients, 0);
    },
  );
  test(
    'health gets no secret; credentials are sent only to the validated destination',
    () async {
      final calls = <http.Request>[];
      final client = HttpRecoveryAdminClient(
        clientFactory: () => MockClient((r) async {
          calls.add(r);
          return http.Response(
            jsonEncode(
              r.url.path == '/sync/health'
                  ? {
                      'server_instance_id': server,
                      'generation_id': generation,
                      'recovery_protocol': 1,
                      'sync_protocol': 2,
                    }
                  : snapshot(),
            ),
            200,
          );
        }),
      );
      final result = await client.inspect(
        mode: AppMode.serverSync,
        destination: 'https://pos.example',
        credential: credential,
      );
      expect(result['revision'], 3);
      expect(calls.first.headers.containsKey('Authorization'), false);
      expect(calls.last.headers['Authorization'], 'Bearer $credential');
      expect(calls.last.headers['X-POS-Generation'], generation);
      expect(calls.every((r) => !r.followRedirects), true);
    },
  );
  test(
    'envía la contraseña Unicode y los espacios exactamente en UTF-8',
    () async {
      const password = '  Mi contraseña de instalación 🔑:  ';
      final client = HttpRecoveryAdminClient(
        clientFactory: () => MockClient((r) async {
          if (r.url.path != '/sync/health') {
            final encoded = r.headers['Authorization']!.substring(6);
            expect(utf8.decode(base64Decode(encoded)), 'admin:$password');
          }
          return http.Response(
            jsonEncode(
              r.url.path == '/sync/health'
                  ? {
                      'server_instance_id': server,
                      'generation_id': generation,
                      'recovery_protocol': 1,
                      'sync_protocol': 2,
                    }
                  : snapshot(),
            ),
            200,
          );
        }),
      );
      await client.inspect(
        mode: AppMode.serverSync,
        destination: 'https://pos.example',
        credential: password,
      );
    },
  );
  test(
    'rechaza contraseñas vacías, excesivas o con controles sin abrir conexiones',
    () async {
      var calls = 0;
      final client = HttpRecoveryAdminClient(
        clientFactory: () {
          calls++;
          throw StateError('No debe conectar');
        },
      );
      for (final secret in [
        '',
        'a' * 129,
        'mi contraseña\ncon salto',
        '\ud800',
      ]) {
        await expectLater(
          client.inspect(
            mode: AppMode.serverSync,
            destination: 'https://pos.example',
            credential: secret,
          ),
          throwsFormatException,
        );
      }
      expect(calls, 0);
    },
  );

  test(
    'rejects a changed identity between health and administrative status',
    () async {
      final client = HttpRecoveryAdminClient(
        clientFactory: () => MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.url.path == '/sync/health'
                  ? {
                      'server_instance_id': server,
                      'generation_id': generation,
                      'recovery_protocol': 1,
                      'sync_protocol': 2,
                    }
                  : {...snapshot(), 'generation_id': server},
            ),
            200,
          ),
        ),
      );
      await expectLater(
        client.inspect(
          mode: AppMode.serverSync,
          destination: 'https://pos.example',
          credential: credential,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'mutation includes destination, known revision and request; no automatic retry',
    () async {
      var calls = 0;
      final client = HttpRecoveryAdminClient(
        clientFactory: () => MockClient((r) async {
          calls++;
          expect(r.method, 'POST');
          expect(r.headers['X-POS-Server'], server);
          expect(jsonDecode(r.body), {
            'action': 'approve',
            'expected_revision': 3,
            'request_id': server,
          });
          return http.Response('{}', 409);
        }),
      );
      await expectLater(
        client.execute(
          mode: AppMode.serverSync,
          destination: 'https://pos.example',
          credential: credential,
          snapshot: snapshot(),
          action: 'approve',
          requestId: server,
        ),
        throwsFormatException,
      );
      expect(calls, 1);
    },
  );
  test(
    'does not follow redirects carrying the administrative credential',
    () async {
      final client = HttpRecoveryAdminClient(
        clientFactory: () => MockClient(
          (r) async => http.Response(
            '',
            302,
            headers: {'location': 'https://other.example'},
          ),
        ),
      );
      await expectLater(
        client.inspect(
          mode: AppMode.serverSync,
          destination: 'https://pos.example',
          credential: credential,
        ),
        throwsFormatException,
      );
    },
  );
}
