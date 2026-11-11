import 'recovery_content_comparer.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../../../application/config/app_config.dart';
import '../../../application/recovery/baseline_bootstrap_service.dart';
import '../../../application/recovery/recovery_attempt_store.dart';
import '../../../application/recovery/recovery_source_binder.dart';
import '../drift/app_database.dart';
import '../drift/recovery_revision_schema.dart';
import 'http_baseline_bootstrap_transport.dart';
import 'sqlite_baseline_bootstrap_installer.dart';
import 'sync_installation_file_store.dart';

/// The final comparison and replacement share Drift's exclusive executor.
/// Every local table has a revision trigger, including excluded drafts/journals.
/// No historical handler runs. The preserved capture is never overwritten.
class DriftRecoverySourceBinder implements RecoverySourceBinder {
  DriftRecoverySourceBinder({
    required this.db,
    required this.directory,
    required this.mode,
    this.beforeCopyForTesting,
    this.afterCopyForTesting,
    this.afterCommitForTesting,
  });
  final AppDatabase db;
  final Directory directory;
  final AppMode Function() mode;
  final Future<void> Function()? beforeCopyForTesting,
      afterCopyForTesting,
      afterCommitForTesting;
  RecoveryAttemptStore get journal =>
      RecoveryAttemptStore(Directory('${directory.path}/source-binding'));
  @override
  Future<void> bind({
    required Map<String, Object?> prepared,
    required Map<String, Object?> attempt,
    required String enrollmentToken,
  }) async {
    if (mode() != AppMode.serverSync || attempt['state'] != 'completed') {
      throw StateError('Se requiere publicación confirmada en server_sync.');
    }
    final progress = attempt['progress'] as Map,
        receipt = progress['receipt'] as Map;
    if (prepared['manifest_digest'] != receipt['manifest_digest'] ||
        prepared['package_id'] != receipt['package_id']) {
      throw const FormatException('Corte de otro paquete.');
    }
    await directory.create(recursive: true);
    final previous = await journal.read();
    if (previous != null &&
        (previous['installation'] as Map?)?['binding'] is Map) {
      final oldBinding = (previous['installation'] as Map)['binding'] as Map;
      final state =
          (await db
                  .customSelect(
                    'SELECT * FROM recovery_local_state WHERE singleton=1',
                  )
                  .getSingle())
              .data;
      if (oldBinding['dataset_id'] == receipt['dataset_id'] &&
          state['dataset_id'] == receipt['dataset_id'] &&
          state['generation_id'] == receipt['generation_id'] &&
          state['server_instance_id'] == receipt['server_instance_id']) {
        await recover(db, directory);
        await db.customStatement('PRAGMA query_only=ON');
        return;
      }
    }
    final cut = Map<String, Object?>.from(prepared['cut'] as Map);
    final snapshot = File(prepared['snapshot_path'] as String);
    if ((await sha256.bind(snapshot.openRead()).first).toString() !=
        cut['snapshot_sha256']) {
      throw const FormatException('Respaldo del origen alterado.');
    }
    final preliminary =
        (await db
                .customSelect(
                  'SELECT * FROM recovery_local_state WHERE singleton=1',
                )
                .getSingle())
            .data;
    if ('${preliminary['data_revision']}' != '${cut['data_revision']}' ||
        preliminary['server_instance_id'] !=
            (cut['source'] as Map)['server_instance_id'] ||
        preliminary['generation_id'] !=
            (cut['source'] as Map)['generation_id'] ||
        preliminary['dataset_id'] != cut['source_dataset_id']) {
      throw StateError(
        'El origen cambió después del corte; se conserva completo.',
      );
    }
    final transport = HttpBaselineBootstrapTransport(
      baseUri: Uri.parse(attempt['destination'] as String),
      serverInstanceId: receipt['server_instance_id'] as String,
      generationId: receipt['generation_id'] as String,
      enrollmentToken: enrollmentToken,
    );
    Map<String, Object?> result;
    try {
      result = await BaselineBootstrapService().installEmpty(
        mode: mode(),
        expectedServer: receipt['server_instance_id'] as String,
        expectedGeneration: receipt['generation_id'] as String,
        expectedDigest: receipt['bootstrap_digest'] as String,
        transport: transport,
        installer: SqliteBaselineBootstrapInstaller(
          Directory('${directory.path}/source-bootstrap'),
        ),
      );
    } finally {
      transport.close();
    }
    final binding = Map<String, Object?>.from(result['binding'] as Map);
    if (binding['device_id'] == (cut['source'] as Map)['device_id']) {
      throw const FormatException('El origen requiere identidad nueva.');
    }
    final installation = <String, Object?>{
      'installation_version': 1,
      'endpoint': attempt['destination'],
      'binding': binding,
      'phase': 'needs_pull',
    };
    SyncInstallationFileStore.validate(installation);
    final staged = result['database_path'] as String;
    await db.exclusively(() async {
      if (mode() != AppMode.serverSync) {
        throw StateError(
          'El modo cambió; se conserva el origen sin sustituir.',
        );
      }
      final current =
          (await db
                  .customSelect(
                    'SELECT * FROM recovery_local_state WHERE singleton=1',
                  )
                  .getSingle())
              .data;
      if ('${current['data_revision']}' != '${cut['data_revision']}' ||
          current['server_instance_id'] !=
              (cut['source'] as Map)['server_instance_id'] ||
          current['generation_id'] != (cut['source'] as Map)['generation_id'] ||
          current['dataset_id'] != cut['source_dataset_id']) {
        throw StateError(
          'El origen cambió después del corte. Se conservan todos sus datos; no se sustituye esta base.',
        );
      }
      final comparison = await directory.createTemp('.final-comparison-');
      try {
        final copy = File('${comparison.path}/source.sqlite');
        await db.customStatement('VACUUM INTO ?', [copy.path]);
        if (!RecoveryContentComparer.matches(snapshot, copy)) {
          throw StateError(
            'El contenido del origen cambió después del corte, incluso si su contador coincide.',
          );
        }
      } finally {
        await comparison.delete(recursive: true);
      }
      await _replace(
        staged,
        installation,
        evidence: {
          'snapshot_path': snapshot.path,
          'snapshot_sha256': cut['snapshot_sha256'],
          'source_revision': cut['data_revision'],
        },
        recheck: () async {
          final locked = await db
              .customSelect(
                'SELECT data_revision FROM recovery_local_state WHERE singleton=1',
              )
              .getSingle();
          if ('${locked.data['data_revision']}' != '${cut['data_revision']}') {
            throw StateError(
              'El origen cambió antes de obtener exclusión SQLite.',
            );
          }
        },
      );
    });
  }

  Future<void> assertEmpty() async {
    final state =
        (await db
                .customSelect(
                  'SELECT * FROM recovery_local_state WHERE singleton=1',
                )
                .getSingle())
            .data;
    if (await SyncInstallationFileStore(directory).read() != null ||
        [
          'dataset_id',
          'generation_id',
          'server_instance_id',
        ].any((k) => state[k] != null)) {
      throw StateError(
        'La instalación ya tiene una vinculación. Se conserva su base.',
      );
    }
    for (final table in recoveryRevisionTables.where(
      (name) => name != 'units',
    )) {
      if ((await db.customSelect('SELECT 1 FROM "$table" LIMIT 1').get())
          .isNotEmpty) {
        throw StateError(
          'La instalación contiene datos o actividad de sincronización. Se conserva su base.',
        );
      }
    }
    final current = await db.select(db.units).get();
    final seed = AppDatabase.inventoryUnitSeed;
    if (current.length != seed.length || !seed.every(current.contains)) {
      throw StateError(
        'El catálogo local de unidades cambió. Se conserva su base.',
      );
    }
  }

  Future<void> installEmpty({
    required String endpoint,
    required Map<String, Object?> staged,
    AppConfig? setupConfig,
  }) async {
    final installation = <String, Object?>{
      'installation_version': 1,
      'endpoint': endpoint,
      'binding': staged['binding'],
      'phase': 'needs_pull',
      if (setupConfig != null) 'setup_config': setupConfig.toJson(),
    };
    SyncInstallationFileStore.validate(installation);
    await db.exclusively(
      () => _replace(
        staged['database_path'] as String,
        installation,
        recheck: assertEmpty,
      ),
    );
  }

  Future<void> _replace(
    String staged,
    Map<String, Object?> installation, {
    Map<String, Object?> evidence = const {},
    required Future<void> Function() recheck,
  }) async {
    await journal.withFileLock(() async {
      await recover(db, directory);
      await recheck();
      final binding = installation['binding'] as Map;
      final prepared = {
        'state': 'prepared',
        'installation': installation,
        'staged_path': staged,
        ...evidence,
      };
      await journal.write(prepared);
      await db.customStatement('ATTACH DATABASE ? AS recovery_baseline', [
        staged,
      ]);
      try {
        await db.transaction(() async {
          await db.customStatement(
            'UPDATE recovery_local_state SET data_revision=data_revision WHERE singleton=1',
          );
          await recheck();
          await beforeCopyForTesting?.call();
          await db.customStatement('PRAGMA defer_foreign_keys=ON');
          for (final table in recoveryRevisionTables) {
            await db.customStatement('DELETE FROM main."$table"');
          }
          for (final table in recoveryRevisionTables) {
            await db.customStatement(
              'INSERT INTO main."$table" SELECT * FROM recovery_baseline."$table"',
            );
          }
          await db.customStatement(
            'UPDATE recovery_local_state SET server_instance_id=?,generation_id=?,dataset_id=? WHERE singleton=1',
            [
              binding['server_instance_id'],
              binding['generation_id'],
              binding['dataset_id'],
            ],
          );
          await afterCopyForTesting?.call();
          if ((await db.customSelect('PRAGMA main.foreign_key_check').get())
              .isNotEmpty) {
            throw StateError('Dependencias de la sustitución inválidas.');
          }
        });
        // Queued writers from the old runtime must fail after replacement,
        // before AppRestartScope can create services with the new identity.
        await db.customStatement('PRAGMA query_only=ON');
        await afterCommitForTesting?.call();
        await SyncInstallationFileStore(directory).write(installation);
        await journal.write({...prepared, 'state': 'installed'});
      } finally {
        await db.customStatement('DETACH DATABASE recovery_baseline');
      }
    });
  }

  /// Called before resolving device ID/endpoint or starting any runtime service.
  static Future<void> recover(AppDatabase db, Directory directory) async {
    final journal = RecoveryAttemptStore(
      Directory('${directory.path}/source-binding'),
    );
    final pending = await journal.read();
    if (pending == null || pending['state'] != 'prepared') return;
    final installation = Map<String, Object?>.from(
          pending['installation'] as Map,
        ),
        binding = installation['binding'] as Map;
    final state =
        (await db
                .customSelect(
                  'SELECT * FROM recovery_local_state WHERE singleton=1',
                )
                .getSingle())
            .data;
    if (state['dataset_id'] == binding['dataset_id'] &&
        state['generation_id'] == binding['generation_id'] &&
        state['server_instance_id'] == binding['server_instance_id']) {
      await SyncInstallationFileStore(directory).write(installation);
      await journal.write({...pending, 'state': 'installed'});
    }
    // A pre-commit interruption leaves the original intact and resumable.
  }
}
