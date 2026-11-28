import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_attempt_store.dart';
import 'package:pos_flutter/application/recovery/recovery_destination_inspector.dart';
import 'package:pos_flutter/application/recovery/recovery_readiness_service.dart';
import 'package:pos_flutter/application/recovery/recovery_snapshot_source.dart';
import 'package:pos_flutter/application/recovery/recovery_transfer_service.dart';
import 'package:pos_flutter/application/sync/sync_installation.dart';
import 'package:pos_flutter/application/sync/sync_network_gate.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/drift_empty_device_enrollment.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_source_binder.dart';
import 'package:pos_flutter/data/local/recovery/http_connection_attempts.dart';
import 'package:pos_flutter/data/local/recovery/sync_installation_file_store.dart';
import 'package:pos_flutter/data/local/sync/guarded_sync_client.dart';

const server = '11111111-1111-4111-8111-111111111111';
const generation = '22222222-2222-4222-8222-222222222222';
const device = '33333333-3333-4333-8333-333333333333';
const dataset = '44444444-4444-4444-8444-444444444444';
final oldUri = Uri.parse('https://old.example');
final newUri = Uri.parse('https://new.example');
final token = 'a' * 64;
Map<String, Object?> health() => {
  'status': 'ok',
  'sync_protocol': 2,
  'recovery_protocol': 1,
  'server_instance_id': server,
  'generation_id': generation,
  'server_mode': 'active',
  'baseline_high_watermark': '42',
};
Map<String, Object?> installation(String phase) => {
  'installation_version': 1,
  'endpoint': '$oldUri',
  'phase': phase,
  'binding': {
    'server_instance_id': server,
    'generation_id': generation,
    'device_id': device,
    'dataset_id': dataset,
    'token': token,
  },
};
http.Response response(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);

class _UnusedInspector implements RecoveryDestinationInspector {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('unused');
}

class _UnusedSource implements RecoverySnapshotSource {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('unused');
}

void main() {
  for (final phase in ['active', 'needs_pull']) {
    test(
      'relocation preserves SQLite and binding in $phase and survives runtime reopening',
      () async {
        final dir = await Directory.systemTemp.createTemp('pos-relocate-');
        addTearDown(() => dir.delete(recursive: true));
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customStatement(
          "INSERT INTO espacios(id,nombre,visibilidad) VALUES('keep','Conservar',0)",
        );
        final before = (await db.select(db.espacios).get()).single;
        final store = SyncInstallationFileStore(dir);
        await store.write(installation(phase));
        final runtime = SyncInstallation(
          await store.read(),
          persist: store.write,
        );
        final gate = SyncNetworkGate(isServerSync: () => true);
        final seen = <http.Request>[];
        final enrollment = DriftEmptyDeviceEnrollment(
          binder: DriftRecoverySourceBinder(
            db: db,
            directory: dir,
            mode: () => AppMode.serverSync,
          ),
          network: gate,
          runtimeInstallation: runtime,
          connections: HttpConnectionAttempts(
            dir,
            clientFactory: () => MockClient((r) async {
              seen.add(r);
              expect(r.followRedirects, false);
              expect(r.url.host, newUri.host);
              if (r.url.path == '/sync/health') return response(health());
              expect(r.url.path, '/sync/pull');
              expect(r.url.queryParameters, {
                'since': '42',
                'limit': '1',
                'device_id': device,
              });
              expect(r.headers['Authorization'], 'Bearer $token');
              expect(r.headers['X-POS-Server'], server);
              expect(r.headers['X-POS-Generation'], generation);
              return response({
                'events': [],
                'next_cursor': 42,
                'has_more': false,
              });
            }),
          ),
        );
        expect(
          await enrollment.checkAndInstall(
            '$newUri',
            mode: AppMode.serverSync,
            onDownloading: () => fail('no bootstrap'),
          ),
          true,
        );
        expect(
          gate.allowsNetwork,
          false,
        ); // Old runtime stays paused until restart.
        expect((await db.select(db.espacios).get()).single, before);
        expect(await store.read(), {
          ...installation(phase),
          'endpoint': '$newUri',
        });
        final reopened = SyncInstallation(
          await store.read(),
          persist: store.write,
        );
        expect(reopened.needsPull, phase == 'needs_pull');
        final client = GuardedSyncClient(
          SyncNetworkGate(isServerSync: () => true),
          MockClient((r) async => response({})),
          installation: reopened,
        );
        addTearDown(client.close);
        await client.get(newUri.resolve('/sync/pull'));
        await expectLater(
          client.get(oldUri.resolve('/sync/pull')),
          throwsStateError,
        );
        expect(seen, hasLength(2));
      },
    );
  }

  for (final failure in [
    'server',
    'generation',
    'recovering',
    'revoked',
    'timeout',
    'redirect',
    'malformed',
  ]) {
    test('$failure retains old installation and resumes old network', () async {
      final dir = await Directory.systemTemp.createTemp(
        'pos-relocate-failure-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final store = SyncInstallationFileStore(dir);
      await store.write(installation('active'));
      final bytes = await store.file.readAsString();
      var authenticated = 0;
      final gate = SyncNetworkGate(isServerSync: () => true);
      final enrollment = DriftEmptyDeviceEnrollment(
        binder: DriftRecoverySourceBinder(
          db: db,
          directory: dir,
          mode: () => AppMode.serverSync,
        ),
        network: gate,
        connections: HttpConnectionAttempts(
          dir,
          clientFactory: () => MockClient((r) async {
            if (r.url.path == '/sync/health') {
              return response({
                ...health(),
                if (failure == 'server') 'server_instance_id': dataset,
                if (failure == 'generation') 'generation_id': dataset,
                if (failure == 'recovering') 'server_mode': 'recovering',
              });
            }
            authenticated++;
            if (failure == 'timeout') throw TimeoutException('offline');
            if (failure == 'redirect') return response({}, 302);
            if (failure == 'malformed') return response({});
            return response({}, 403);
          }),
        ),
      );
      await expectLater(
        enrollment.checkAndInstall(
          '$newUri',
          mode: AppMode.serverSync,
          onDownloading: () {},
        ),
        throwsA(anything),
      );
      expect(await store.file.readAsString(), bytes);
      expect(gate.allowsNetwork, true);
      expect(
        authenticated,
        ['server', 'generation', 'recovering'].contains(failure) ? 0 : 1,
      );
    });
  }

  for (final scenario in [
    'receiving',
    'lost-creation-response',
    'before-creation',
    'completed',
    'wrong-package',
    'other-server',
  ]) {
    test(
      'recovery relocation $scenario reuses original proof and preserves progress',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'pos-recovery-relocate-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final package = <String, Object?>{
          'package_id': dataset,
          'manifest_digest': 'b' * 64,
          'cut': {
            'source': {'device_id': device},
          },
        };
        String? proof, requestId;
        var relocated = false;
        final connections = HttpConnectionAttempts(
          Directory('${dir.path}/connections'),
          clientFactory: () => MockClient((r) async {
            expect(r.followRedirects, false);
            if (r.url.path == '/sync/health') {
              return response({
                ...health(),
                if (scenario == 'other-server') 'server_instance_id': dataset,
              });
            }
            if (r.url.path == '/recovery/connection-request') {
              final body = jsonDecode(r.body) as Map;
              proof ??= r.headers['Authorization'];
              requestId ??= body['request_id'] as String;
              expect(r.headers['Authorization'], proof);
              expect(body['request_id'], requestId);
              expect(body['manifest_digest'], package['manifest_digest']);
              return response({'status': 'approved', 'token': token});
            }
            expect(r.headers['Authorization'], 'Bearer $token');
            if (scenario == 'before-creation' &&
                r.url.path.startsWith('/recovery/sessions/')) {
              return response({'code': 'session_not_found'}, 404);
            }
            if (scenario == 'before-creation') {
              expect(r.url.path, '/recovery/eligibility');
            } else {
              expect(r.url.path, '/recovery/sessions/$requestId');
            }
            return response({
              'protocol_version': 1,
              'server_instance_id': server,
              'generation_id': generation,
              'recovery_id': requestId,
              'eligible': true,
              'manifest_digest': scenario == 'wrong-package'
                  ? 'wrong'
                  : package['manifest_digest'],
            });
          }),
        );
        final approval = await connections.recovery(
          oldUri,
          server,
          generation,
          package,
        );
        final original = <String, Object?>{
          'journal_version': 1,
          'destination': '$oldUri',
          'server_instance_id': server,
          'generation_id': generation,
          'recovery_token': token,
          'connection_request_id': approval['request_id'],
          'recovery_id':
              ['lost-creation-response', 'before-creation'].contains(scenario)
              ? null
              : requestId,
          'state': scenario == 'completed' ? 'completed' : 'receiving',
          'manifest_digest': package['manifest_digest'],
          'prepared_source': package,
          'package_id': dataset,
          'received_chunks': 7,
          'total_chunks': 10,
          'progress': {
            'receipt': {'dataset_id': dataset},
          },
        };
        final store = RecoveryAttemptStore(Directory('${dir.path}/attempt'));
        await store.write(original);
        final service = RecoveryTransferService(store);
        if (['wrong-package', 'other-server'].contains(scenario)) {
          await expectLater(
            service.relocate(newUri, connections.verifyRecoveryRelocation),
            throwsA(anything),
          );
          expect(await store.read(), original);
        } else {
          await service.relocate(newUri, connections.verifyRecoveryRelocation);
          relocated = true;
          expect(await store.read(), {...original, 'destination': '$newUri'});
          // Normal refresh at the new URL must still locate the original proof.
          final refreshed = await connections.authorizeRecovery(
            newUri,
            package,
            inspector: _UnusedInspector(),
            server: server,
            generation: generation,
          );
          expect(refreshed['request_id'], approval['request_id']);
        }
        expect(
          relocated,
          !['wrong-package', 'other-server'].contains(scenario),
        );
      },
    );
  }

  test('standalone relocation never invokes verification or network', () async {
    var called = false;
    final service = RecoveryReadinessService(
      source: _UnusedSource(),
      privateDirectory: () async => throw StateError('no filesystem access'),
      deviceId: device,
      appRevision: 'test',
      verifyRelocation: (_, _) async {
        called = true;
        return {};
      },
    );
    await expectLater(
      service.relocateDestination('$newUri', AppMode.standalone),
      throwsStateError,
    );
    expect(called, false);
  });
}
