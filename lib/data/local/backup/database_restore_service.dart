import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../application/backup/backup_service.dart';
import '../drift/app_database.dart';
import '../drift/current_database_schema.dart';
import '../drift/offer_pricing_schema.dart';
import 'safe_database_replacement.dart';

class DriftDatabaseRestoreService implements DatabaseRestoreService {
  DriftDatabaseRestoreService({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> restoreSnapshot(
    File snapshotFile, {
    required String sha256,
  }) async {
    final wal = File('${snapshotFile.path}-wal');
    if (await wal.exists() && await wal.length() > 0) {
      throw StateError(
        'El respaldo tiene WAL pendiente; se requiere una captura consistente exportada.',
      );
    }
    final actualSha = await _sha256(snapshotFile);
    if (actualSha != sha256) {
      throw StateError('El respaldo descargado no coincide con el sha256.');
    }

    final databaseFile = await appDatabaseFile();
    final stagingDir = await databaseFile.parent.createTemp(
      'pos-restore-staging-',
    );
    final staged = File('${stagingDir.path}/database');
    try {
      await snapshotFile.copy(staged.path);
      if (await _sha256(staged) != sha256) {
        throw StateError('El respaldo cambió durante su copia.');
      }
      // El hash y el origen permanecen intactos: migración solo sobre staging.
      await prepareAppDatabase(staged);
      _validateIntegrity(staged, schemaVersion: _db.schemaVersion);
      await _db.close();
      await replaceDatabaseSafely(
        databaseFile,
        staged,
        markRestored: markAppDatabaseAsRestored,
      );
    } finally {
      await stagingDir.delete(recursive: true);
    }
  }
}

void _validateIntegrity(File databaseFile, {required int schemaVersion}) {
  final sqlite = sqlite3.open(databaseFile.path);
  try {
    final result = sqlite.select('PRAGMA integrity_check');
    final value = result.isEmpty ? null : result.first.values.first;
    if (value != 'ok') {
      throw StateError('El respaldo descargado no paso integrity_check.');
    }
    final version = sqlite.select('PRAGMA user_version').single.values.single;
    if (version != schemaVersion || !hasCurrentAppDatabaseSchema(sqlite)) {
      throw StateError(
        'El respaldo no contiene el esquema actual de la aplicación.',
      );
    }
    if (sqlite.select('PRAGMA foreign_key_check').isNotEmpty) {
      throw StateError('El respaldo contiene referencias inválidas.');
    }
  } finally {
    sqlite.close();
  }
}

Future<String> _sha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
