import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_source_binder.dart';
import 'package:pos_flutter/data/local/recovery/recovery_content_comparer.dart';
import 'package:pos_flutter/data/local/recovery/sync_installation_file_store.dart';

void main() {
  test('source binding SIGKILL and fresh-process recovery', () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final path = Platform.environment['POS_RECOVERY_S5_BINDING']!;
    if (!path.startsWith('/tmp/pos-recovery-s4-')) {
      throw StateError('Isolated fixture required');
    }
    final input = jsonDecode(await File(path).readAsString()) as Map,
        root = File(path).parent;
    final prepared = Map<String, Object?>.from(
          jsonDecode(
                await File('${root.path}/source-prepared.json').readAsString(),
              )
              as Map,
        ),
        source = File(prepared['snapshot_path'] as String);
    final phase = input['crash_phase'] as String,
        mode = Platform.environment['POS_RECOVERY_S5_CRASH_MODE'];
    final target = File('${root.path}/crash-$phase.sqlite'),
        directory = Directory('${root.path}/crash-$phase');
    if (mode == 'crash') await source.copy(target.path);
    final db = AppDatabase.forTesting(NativeDatabase(target));
    if (mode == 'crash') {
      Future<void> terminate() async {
        await File(
          '${root.path}/killed-$phase.json',
        ).writeAsString(jsonEncode({'phase': phase, 'pid': pid}), flush: true);
        Process.killPid(pid, ProcessSignal.sigkill);
        await Completer<void>().future;
      }

      await DriftRecoverySourceBinder(
        db: db,
        directory: directory,
        mode: () => AppMode.serverSync,
        afterCopyForTesting: phase == 'before' ? terminate : null,
        afterCommitForTesting: phase == 'after' ? terminate : null,
      ).bind(
        prepared: prepared,
        attempt: {
          'state': 'completed',
          'destination': input['url'],
          'progress': {'receipt': input['receipt']},
        },
        enrollmentToken: input['token'] as String,
      );
      fail('SIGKILL phase not reached');
    } else {
      await DriftRecoverySourceBinder.recover(db, directory);
      final state =
          (await db
                  .customSelect('SELECT * FROM recovery_local_state')
                  .getSingle())
              .data;
      if (phase == 'before') {
        expect(
          state['dataset_id'],
          (prepared['cut'] as Map)['source_dataset_id'],
        );
        expect(await SyncInstallationFileStore(directory).read(), isNull);
        final comparison = File('${root.path}/crash-before-comparison.sqlite');
        await db.customStatement('VACUUM INTO ?', [comparison.path]);
        expect(RecoveryContentComparer.matches(source, comparison), isTrue);
      } else {
        expect(state['dataset_id'], (input['receipt'] as Map)['dataset_id']);
        expect(
          (await SyncInstallationFileStore(directory).read())!['phase'],
          'needs_pull',
        );
        expect(await db.select(db.sales).get(), hasLength(6));
        expect(
          (await db.select(db.events).get()).any(
            (e) => e.deliveryStatus == 'pending',
          ),
          isFalse,
        );
      }
      await db.close();
    }
  });
}
