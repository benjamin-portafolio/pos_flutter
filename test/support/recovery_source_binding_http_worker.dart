import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:pos_flutter/application/sync/sync_installation.dart';
import 'package:pos_flutter/application/sync/sync_network_gate.dart';
import 'package:pos_flutter/application/sync/sync_pull_service.dart';
import 'package:pos_flutter/application/sync/sync_socket_listener.dart';
import 'package:pos_flutter/application/sync/sync_endpoint_config.dart';
import 'package:pos_flutter/application/commands/local_command_context.dart';
import 'package:pos_flutter/application/commands/inventario/registrar_movimiento_inventario_command.dart';
import 'package:pos_flutter/domain/inventario/tipo_movimiento_inventario.dart';
import 'package:pos_flutter/data/local/sync/guarded_sync_client.dart';
import 'variant_tracking_harness.dart';
import 'dart:async';
// S5 original-device replacement, only with synthetic copies under /tmp.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_json.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/recovery_revision_schema.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_source_binder.dart';
import 'package:pos_flutter/data/local/recovery/sync_installation_file_store.dart';
import 'package:pos_flutter/application/recovery/recovery_attempt_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'source binding conserves every post-cut table, excludes queued writers and recovers local commit',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final inputPath = Platform.environment['POS_RECOVERY_S5_BINDING']!;
      if (!inputPath.startsWith('/tmp/pos-recovery-s4-')) {
        throw StateError('Isolated fixture required');
      }
      final input = jsonDecode(await File(inputPath).readAsString()) as Map;
      final root = File(inputPath).parent,
          prepared = Map<String, Object?>.from(
            jsonDecode(
                  await File(
                    '${root.path}/source-prepared.json',
                  ).readAsString(),
                )
                as Map,
          );
      final callerZone = Zone.current;
      var writerSequence = 0;
      Future<void> writeAfterBaseline(String label) async {
        final actor = input['writer_binding'] as Map,
            client = HttpClient()
              ..connectionTimeout = const Duration(seconds: 10);
        try {
          final request = await client.postUrl(
            Uri.parse('${input['url']}/sync/push'),
          );
          for (final entry in {
            'X-POS-Protocol': '2',
            'X-POS-Server': actor['server_instance_id'],
            'X-POS-Generation': actor['generation_id'],
            'X-POS-Device': actor['device_id'],
            'Authorization': 'Bearer ${actor['token']}',
          }.entries) {
            request.headers.set(entry.key, entry.value!);
          }
          final eventId = const Uuid().v4();
          request.headers.contentType = ContentType.json;
          request.write(
            jsonEncode({
              'device_id': actor['device_id'],
              'last_full_pull_server_sequence': int.parse(
                (input['receipt'] as Map)['baseline_high_watermark'] as String,
              ),
              'last_preflight_server_sequence': int.parse(
                (input['receipt'] as Map)['baseline_high_watermark'] as String,
              ),
              'events': [
                {
                  'event_id': eventId,
                  'aggregate_id': const Uuid().v4(),
                  'aggregate_type': 'supplier',
                  'event_type': 'proveedor_creado',
                  'device_id': actor['device_id'],
                  'user_id': 'fixture-late-writer',
                  'local_sequence': ++writerSequence,
                  'base_version': 1,
                  'base_server_sequence': null,
                  'created_at_local': DateTime.now().toUtc().toIso8601String(),
                  'payload': {
                    'name': 'Proveedor $label',
                    'phone': null,
                    'notes': null,
                  },
                },
              ],
            }),
          );
          final response = await request.close(),
              body = await utf8.decodeStream(response);
          expect(response.statusCode, inInclusiveRange(200, 299), reason: body);
          expect(
            ((jsonDecode(body) as Map)['results'] as List).single['status'],
            'accepted',
            reason: body,
          );
        } finally {
          client.close(force: true);
        }
      }

      final source = File(prepared['snapshot_path'] as String),
          originalDigest = (await sha256.bind(source.openRead()).first)
              .toString();
      final attempt = <String, Object?>{
        'state': 'completed',
        'destination': input['url'],
        'progress': {'receipt': input['receipt']},
      };
      Future<AppDatabase> copy(String name) async {
        final file = await source.copy('${root.path}/source-$name.sqlite');
        return AppDatabase.forTesting(NativeDatabase(file));
      }

      Future<Map<String, Object?>> content(AppDatabase db) async => {
        for (final table in recoveryRevisionTables)
          table:
              (await db.customSelect('SELECT * FROM "$table"').get())
                  .map((r) => recoveryCanonical(r.data))
                  .toList()
                ..sort(),
      };
      final inventory = await copy('inventory');
      final populated = <String>[];
      for (final table in recoveryRevisionTables) {
        if ((await inventory
                .customSelect('SELECT 1 FROM "$table" LIMIT 1')
                .get())
            .isNotEmpty) {
          populated.add(table);
        }
      }
      await inventory.close();
      for (final table in populated) {
        final db = await copy(table),
            directory = Directory('${root.path}/bind-$table');
        try {
          final column =
              (await db.customSelect('PRAGMA table_info("$table")').get()).first
                  .read<String>('name');
          await db.customStatement('UPDATE "$table" SET "$column"="$column"');
          final before = await content(db);
          await expectLater(
            DriftRecoverySourceBinder(
              db: db,
              directory: directory,
              mode: () => AppMode.serverSync,
            ).bind(
              prepared: prepared,
              attempt: attempt,
              enrollmentToken: input['token'] as String,
            ),
            throwsStateError,
            reason: 'post-cut $table',
          );
          expect(await content(db), before, reason: 'preserve $table');
          expect(await SyncInstallationFileStore(directory).read(), isNull);
        } finally {
          await db.close();
        }
      }
      // A restored/reused counter cannot conceal altered content.
      final reused = await copy('reused-counter');
      await reused.customStatement(
        "UPDATE suppliers SET name='Post-cut preserved'",
      );
      await reused.customStatement(
        'UPDATE recovery_local_state SET data_revision=?',
        [(prepared['cut'] as Map)['data_revision']],
      );
      final reusedBefore = await content(reused);
      await expectLater(
        DriftRecoverySourceBinder(
          db: reused,
          directory: Directory('${root.path}/bind-reused'),
          mode: () => AppMode.serverSync,
        ).bind(
          prepared: prepared,
          attempt: attempt,
          enrollmentToken: input['token'] as String,
        ),
        throwsStateError,
      );
      expect(await content(reused), reusedBefore);
      await reused.close();
      for (final phase in ['rollback', 'commit', 'normal']) {
        final db = await copy(phase),
            directory = Directory('${root.path}/bind-$phase');
        Future<void>? queued;
        bool writerRejected = false;
        final before = await content(db);
        final binder = DriftRecoverySourceBinder(
          db: db,
          directory: directory,
          mode: () => AppMode.serverSync,
          beforeCopyForTesting: () async {
            if (phase == 'normal') {
              await writeAfterBaseline('durante sustitución');
            }
            queued = callerZone
                .run(() => db.customStatement('UPDATE units SET active=active'))
                .catchError((Object error) {
                  writerRejected = true;
                });
          },
          afterCopyForTesting: () async {
            final raw = sqlite.sqlite3.open(
              '${root.path}/source-$phase.sqlite',
              mode: sqlite.OpenMode.readOnly,
            );
            try {
              expect(
                raw
                    .select('SELECT dataset_id FROM recovery_local_state')
                    .single['dataset_id'],
                (prepared['cut'] as Map)['source_dataset_id'],
              );
            } on sqlite.SqliteException catch (error) {
              // Rollback-journal page spill may take EXCLUSIVE before commit.
              // BUSY is safe: a second connection never observes partial rows.
              // The checks after rollback/commit below still require exact data.
              if (error.resultCode != 5) rethrow;
              stdout.writeln(
                'S6 reader blocked by atomic SQLite replacement (SQLITE_BUSY)',
              );
            } finally {
              raw.close();
            }
            if (phase == 'rollback') {
              throw StateError('Synthetic interruption before commit');
            }
          },
          afterCommitForTesting: phase == 'commit'
              ? () async {
                  throw StateError(
                    'Synthetic interruption after commit before identity file',
                  );
                }
              : null,
        );
        if (phase == 'rollback') {
          await expectLater(
            binder.bind(
              prepared: prepared,
              attempt: attempt,
              enrollmentToken: input['token'] as String,
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('Synthetic interruption before commit'),
              ),
            ),
          );
          await queued;
          expect(await content(db), before);
          expect(await SyncInstallationFileStore(directory).read(), isNull);
          await db.close();
          continue;
        }
        if (phase == 'commit') {
          await expectLater(
            binder.bind(
              prepared: prepared,
              attempt: attempt,
              enrollmentToken: input['token'] as String,
            ),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'message',
                contains('Synthetic interruption after commit'),
              ),
            ),
          );
        } else {
          await binder.bind(
            prepared: prepared,
            attempt: attempt,
            enrollmentToken: input['token'] as String,
          );
        }
        await queued;
        expect(writerRejected, isTrue);
        final installedState =
            (await db
                    .customSelect('SELECT * FROM recovery_local_state')
                    .getSingle())
                .data;
        expect(
          installedState['dataset_id'],
          (input['receipt'] as Map)['dataset_id'],
        );
        expect(
          installedState['generation_id'],
          (input['receipt'] as Map)['generation_id'],
        );
        expect(await db.select(db.sales).get(), hasLength(6));
        expect(
          (await db.select(db.events).get()).any(
            (e) => e.deliveryStatus == 'pending',
          ),
          isFalse,
        );
        await db.close();
        final reopened = AppDatabase.forTesting(
          NativeDatabase(File('${root.path}/source-$phase.sqlite')),
        );
        addTearDown(reopened.close);
        await DriftRecoverySourceBinder.recover(reopened, directory);
        final installation = (await SyncInstallationFileStore(
          directory,
        ).read())!;
        expect(installation['phase'], 'needs_pull');
        expect(
          (installation['binding'] as Map)['device_id'],
          isNot(
            (prepared['cut'] as Map)['source'] is Map
                ? ((prepared['cut'] as Map)['source'] as Map)['device_id']
                : null,
          ),
        );
        expect(
          await reopened.syncCheckpointDao.obtenerLastFullPullServerSequence(),
          int.parse(
            (input['receipt'] as Map)['baseline_high_watermark'] as String,
          ),
        );
        expect(
          (await RecoveryAttemptStore(
            Directory('${directory.path}/source-binding'),
          ).read())!['state'],
          'installed',
        );
        if (phase == 'normal') {
          final store = SyncInstallationFileStore(directory),
              identity = SyncInstallation(installation, persist: store.write),
              binding = installation['binding'] as Map;
          final h = VariantTrackingHarness(
            database: reopened,
            mode: AppMode.serverSync,
            context: LocalCommandContext(
              deviceId: binding['device_id'] as String,
              userId: 'source-new-operator',
            ),
            isolatedSyncHarness: true,
          );
          final client = GuardedSyncClient(
            SyncNetworkGate(isServerSync: () => true),
            http.Client(),
            installation: identity,
          );
          final pull = SyncPullService(
            syncPersistence: h.history,
            remoteEventApplier: h.remote,
            endpointConfig: SyncEndpointConfig(
              initialBaseUrl: input['url'] as String,
            ),
            commandContext: h.context,
            client: client,
          );
          try {
            expect(identity.needsPull, isTrue);
            final first = await pull.pullAvailableEvents();
            expect(first.total, greaterThanOrEqualTo(1));
            expect(
              (await reopened.select(reopened.suppliers).get()).any(
                (s) => s.name == 'Proveedor durante sustitución',
              ),
              isTrue,
            );
            await identity.activate();
            expect((await store.read())!['phase'], 'active');
            final listener = SyncSocketListener(
              endpointConfig: SyncEndpointConfig(
                initialBaseUrl: input['url'] as String,
              ),
              commandContext: h.context,
              syncPersistence: h.history,
              allowsNetwork: () => !identity.needsPull,
              authentication: () => {
                'protocol': '2',
                'server_instance_id': binding['server_instance_id'],
                'generation_id': binding['generation_id'],
                'device_id': binding['device_id'],
                'token': binding['token'],
              },
            );
            addTearDown(listener.stop);
            final connected = listener.connectionEstablished.first.timeout(
                  const Duration(seconds: 10),
                ),
                notice = listener.eventsAvailable.first.timeout(
                  const Duration(seconds: 10),
                );
            listener.start();
            await connected;
            await writeAfterBaseline('WebSocket vinculado');
            expect(
              (await notice).latestServerSequence,
              greaterThan(
                int.parse(
                  (input['receipt'] as Map)['baseline_high_watermark']
                      as String,
                ),
              ),
            );
            listener.stop();
            await pull.pullAvailableEvents();
            expect(
              (await reopened.select(reopened.suppliers).get()).any(
                (s) => s.name == 'Proveedor WebSocket vinculado',
              ),
              isTrue,
            );
            final item = (await reopened.select(reopened.inventoryItems).get())
                    .firstWhere((i) => i.active),
                before =
                    (await reopened.select(reopened.inventoryBalances).get())
                        .firstWhere((b) => b.inventoryItemId == item.id)
                        .quantityOnHandAtomic;
            await h.inventoryCommands.registrarMovimiento(
              RegistrarMovimientoInventarioCommand(
                inventoryItemId: item.id,
                movementType: TipoMovimientoInventario.stockReceipt,
                quantityDeltaAtomic: 3,
              ),
            );
            expect(
              (await h
                      .push(input['url'] as String, client: client)
                      .pushPendingEvents())
                  .synced,
              1,
            );
            await pull.pullAvailableEvents();
            await pull.pullAvailableEvents();
            expect(await h.history.pendingEvents(), isEmpty);
            expect(
              (await reopened.select(reopened.inventoryBalances).get())
                  .firstWhere((b) => b.inventoryItemId == item.id)
                  .quantityOnHandAtomic,
              before + 3,
            );
          } finally {
            client.close();
          }
        }
        await reopened.close();
      }
      expect(
        (await sha256.bind(source.openRead()).first).toString(),
        originalDigest,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
