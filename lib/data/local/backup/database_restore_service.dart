import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../application/backup/backup_service.dart';
import '../drift/app_database.dart';

class DriftDatabaseRestoreService implements DatabaseRestoreService {
  DriftDatabaseRestoreService({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  @override
  Future<void> restoreSnapshot(
    File snapshotFile, {
    required String sha256,
  }) async {
    final actualSha = await _sha256(snapshotFile);
    if (actualSha != sha256) {
      throw StateError('El respaldo descargado no coincide con el sha256.');
    }

    _validateIntegrity(snapshotFile);

    final databaseFile = await appDatabaseFile();
    await _db.close();
    await _deleteDatabaseFiles(databaseFile);
    await snapshotFile.copy(databaseFile.path);
    await markAppDatabaseAsRestored();
  }
}

void _validateIntegrity(File databaseFile) {
  final sqlite = sqlite3.open(databaseFile.path);
  try {
    final result = sqlite.select('PRAGMA integrity_check');
    final value = result.isEmpty ? null : result.first.values.first;
    if (value != 'ok') {
      throw StateError('El respaldo descargado no paso integrity_check.');
    }
  } finally {
    sqlite.close();
  }
}

Future<void> _deleteDatabaseFiles(File databaseFile) async {
  final databasePaths = [
    databaseFile.path,
    '${databaseFile.path}-wal',
    '${databaseFile.path}-shm',
  ];

  for (final path in databasePaths) {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

Future<String> _sha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
