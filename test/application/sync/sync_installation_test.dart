import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/sync/sync_installation.dart';
import 'package:pos_flutter/application/sync/sync_network_gate.dart';
import 'package:pos_flutter/data/local/sync/guarded_sync_client.dart';

void main() {
  test(
    'every operational transport uses only the bound generation and token; cross-endpoint and early push blocked',
    () async {
      final saved = <Map<String, Object?>>[], seen = <http.Request>[];
      final installation = SyncInstallation(
        {
          'endpoint': 'https://destination.example',
          'phase': 'needs_pull',
          'binding': {
            'server_instance_id': 'server-new',
            'generation_id': 'generation-new',
            'device_id': 'device-new',
            'token': 'operational-token',
          },
        },
        persist: (v) async {
          saved.add(v);
        },
      );
      final client = GuardedSyncClient(
        SyncNetworkGate(isServerSync: () => true),
        MockClient((r) async {
          seen.add(r);
          return http.Response('{}', 200);
        }),
        installation: installation,
      );
      for (final path in [
        '/sync/push',
        '/sync/preflight',
        '/sync/conflict-reports',
      ]) {
        await expectLater(
          client.post(Uri.parse('https://destination.example$path')),
          throwsStateError,
        );
      }
      await expectLater(
        client.get(Uri.parse('https://old.example/sync/pull')),
        throwsStateError,
      );
      expect(seen, isEmpty);
      await client.get(
        Uri.parse('https://destination.example/sync/pull?since=100'),
      );
      await installation.activate();
      expect(saved.single['phase'], 'active');
      for (final path in [
        '/sync/health',
        '/sync/push',
        '/sync/pull',
        '/sync/preflight',
        '/sync/conflict-reports',
      ]) {
        await client.get(Uri.parse('https://destination.example$path'));
      }
      expect(seen, hasLength(6));
      for (final request in seen) {
        expect(request.headers['Authorization'], 'Bearer operational-token');
        expect(request.headers['X-POS-Protocol'], '2');
        expect(request.headers['X-POS-Generation'], 'generation-new');
        expect(request.headers['X-POS-Device'], 'device-new');
        expect(request.followRedirects, isFalse);
      }
      client.close();
    },
  );
  test(
    'activation and relocation serialize without restoring the old endpoint',
    () async {
      final firstWrite = Completer<void>();
      final saved = <Map<String, Object?>>[];
      final installation = SyncInstallation(
        {
          'endpoint': 'https://old.example',
          'phase': 'needs_pull',
          'binding': {'token': 'keep'},
        },
        persist: (value) async {
          saved.add(value);
          if (saved.length == 1) await firstWrite.future;
        },
      );
      final activation = installation.activate();
      await Future<void>.delayed(Duration.zero);
      final relocation = installation.relocate('https://new.example');
      expect(saved, hasLength(1));
      firstWrite.complete();
      await Future.wait([activation, relocation]);
      expect(saved.last, {
        'endpoint': 'https://new.example',
        'phase': 'active',
        'binding': {'token': 'keep'},
      });
      expect(
        installation.allows(Uri.parse('https://old.example/sync/pull')),
        false,
      );
      expect(
        installation.allows(Uri.parse('https://new.example/sync/push')),
        true,
      );
    },
  );

  test('failed activation persistence retains the gate and binding', () async {
    final installation = SyncInstallation(
      {'phase': 'needs_pull', 'endpoint': 'https://new.example'},
      persist: (_) async {
        throw StateError('disk unavailable');
      },
    );
    await expectLater(installation.activate(), throwsStateError);
    expect(installation.needsPull, isTrue);
  });
}
