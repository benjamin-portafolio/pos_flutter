import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/sync/sync_installation.dart';
import 'package:pos_flutter/application/sync/sync_network_gate.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/drift_empty_device_enrollment.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_source_binder.dart';
import 'package:pos_flutter/data/local/recovery/http_connection_attempts.dart';
import 'package:pos_flutter/data/local/recovery/sync_installation_file_store.dart';
import 'package:pos_flutter/data/local/sync/guarded_sync_client.dart';

import 'variant_tracking_harness.dart';

void main() {
  final url = Platform.environment['POS_CONNECTION_RECOVERY_FIXTURE'];
  test(
    'alta por URL, conservación, reparación del commit y primer pull',
    () async {
      expect(Uri.parse(url!).host, '127.0.0.1');
      final directory = await Directory.systemTemp.createTemp(
        'pos-connection-fixture-',
      );
      final file = File('${directory.path}/operative.sqlite');
      final connections = HttpConnectionAttempts(
        Directory('${directory.path}/attempts'),
      );
      final network = SyncNetworkGate(isServerSync: () => true);
      final store = SyncInstallationFileStore(directory);
      var db = AppDatabase.forTesting(NativeDatabase(file));
      const mode = AppMode.serverSync;
      var stopAfterCommit = false;
      final enrollment = DriftEmptyDeviceEnrollment(
        connections: connections,
        binder: DriftRecoverySourceBinder(
          db: db,
          directory: directory,
          mode: () => mode,
          afterCommitForTesting: () async {
            if (stopAfterCommit) {
              throw StateError('simulated exit after SQLite commit');
            }
          },
        ),
        network: network,
      );
      final initialConfig = AppConfig.initial.copyWith(
        mode: mode,
        setupCompleted: true,
        cashEnabled: false,
      );
      Future<bool> install() => enrollment.checkAndInstall(
        url,
        mode: mode,
        setupConfig: initialConfig,
        onDownloading: () {},
      );
      try {
        await db.customStatement(
          "INSERT INTO espacios(id,nombre,visibilidad) VALUES('existing','Local',0)",
        );
        await expectLater(
          install(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('contiene datos'),
            ),
          ),
        );
        expect(await db.select(db.espacios).get(), hasLength(1));
        expect(await store.read(), isNull);
        await db.customStatement("DELETE FROM espacios WHERE id='existing'");
        stopAfterCommit = true;
        await expectLater(
          install(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('simulated exit'),
            ),
          ),
        );
        expect(await store.read(), isNull);
        await db.close();

        db = AppDatabase.forTesting(NativeDatabase(file));
        await DriftRecoverySourceBinder.recover(db, directory);
        final saved = (await store.read())!;
        expect(saved['phase'], 'needs_pull');
        expect(saved['endpoint'], url);
        final recoveredConfig = AppConfig.fromJson(
          Map<String, Object?>.from(saved['setup_config'] as Map),
        );
        expect(recoveredConfig.setupCompleted, isTrue);
        expect(recoveredConfig.mode, mode);
        expect(recoveredConfig.cashEnabled, isFalse);
        final binding = saved['binding'] as Map;
        final device = binding['device_id'] as String;
        final cut = int.parse(binding['baseline_high_watermark'] as String);
        final harness = VariantTrackingHarness(
          database: db,
          mode: mode,
          context: LocalCommandContext(
            deviceId: device,
            userId: 'fixture-client',
          ),
          isolatedSyncHarness: true,
        );
        expect(await harness.history.lastFullPullServerSequence(), cut);
        expect(await db.select(db.suppliers).get(), hasLength(1));
        final installation = SyncInstallation(saved, persist: store.write);
        final client = GuardedSyncClient(
          SyncNetworkGate(isServerSync: () => true),
          http.Client(),
          installation: installation,
        );
        try {
          expect(installation.allows(Uri.parse('$url/sync/push')), isFalse);
          final report = await SyncPullService(
            syncPersistence: harness.history,
            remoteEventApplier: harness.remote,
            endpointConfig: SyncEndpointConfig(initialBaseUrl: url),
            commandContext: harness.context,
            client: client,
          ).pullAvailableEvents();
          expect(report.lastCursor, greaterThan(cut));
          expect(await db.select(db.suppliers).get(), hasLength(2));
          await installation.activate();
          expect((await store.read())!['phase'], 'active');
        } finally {
          client.close();
        }

        await db.close();
        db = AppDatabase.forTesting(NativeDatabase(file));
        expect((await (db.select(db.suppliers)).get()), hasLength(2));
        expect(((await store.read())!['binding'] as Map)['device_id'], device);
        expect(
          await db.syncCheckpointDao.obtenerLastFullPullServerSequence(),
          greaterThan(cut),
        );
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
    skip: url == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  final normalUrl = Platform.environment['POS_CONNECTION_NORMAL_FIXTURE'];
  test(
    'servidor normal conserva la base y permite pull sin binding',
    () async {
      expect(Uri.parse(normalUrl!).host, '127.0.0.1');
      final directory = await Directory.systemTemp.createTemp(
        'pos-normal-fixture-',
      );
      final harness = VariantTrackingHarness(mode: AppMode.serverSync);
      final network = SyncNetworkGate(isServerSync: () => true);
      final enrollment = DriftEmptyDeviceEnrollment(
        connections: HttpConnectionAttempts(
          Directory('${directory.path}/attempts'),
        ),
        binder: DriftRecoverySourceBinder(
          db: harness.db,
          directory: directory,
          mode: () => AppMode.serverSync,
        ),
        network: network,
      );
      final client = GuardedSyncClient(network, http.Client());
      try {
        expect(
          await enrollment.checkAndInstall(
            normalUrl,
            mode: AppMode.serverSync,
            onDownloading: () =>
                fail('Un servidor normal no descarga un baseline'),
          ),
          isFalse,
        );
        expect(await SyncInstallationFileStore(directory).read(), isNull);
        final report = await SyncPullService(
          syncPersistence: harness.history,
          remoteEventApplier: harness.remote,
          endpointConfig: SyncEndpointConfig(initialBaseUrl: normalUrl),
          commandContext: harness.context,
          client: client,
        ).pullAvailableEvents();
        expect(report.lastCursor, 0);
      } finally {
        client.close();
        await harness.db.close();
        await directory.delete(recursive: true);
      }
    },
    skip: normalUrl == null,
  );
}
