import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../../application/backup/backup_manifest.dart';
import '../../../application/backup/backup_service.dart';
import '../drift/app_database.dart';

class DriftDatabaseSnapshotService implements DatabaseSnapshotService {
  DriftDatabaseSnapshotService({
    required AppDatabase db,
    required DatabaseStateReader stateReader,
  }) : _db = db,
       _stateReader = stateReader;

  final AppDatabase _db;
  final DatabaseStateReader _stateReader;

  @override
  Future<DatabaseSnapshot> createSnapshot() async {
    final tempDir = await Directory.systemTemp.createTemp('pos_backup_');
    final snapshotFile = File(
      p.join(tempDir.path, BackupManifest.latestDatabaseFileName),
    );

    await _db.customStatement('VACUUM INTO ?', [snapshotFile.path]);
    _validateIntegrity(snapshotFile);

    final state = await _stateReader.readState();
    return DatabaseSnapshot(
      file: snapshotFile,
      schemaVersion: _db.schemaVersion,
      eventCount: state.eventCount,
      lastLocalSequence: state.lastLocalSequence,
      sha256: await _sha256(snapshotFile),
    );
  }
}

void _validateIntegrity(File databaseFile) {
  final sqlite = sqlite3.open(databaseFile.path);
  try {
    final result = sqlite.select('PRAGMA integrity_check');
    final value = result.isEmpty ? null : result.first.values.first;
    if (value != 'ok') {
      throw StateError('El snapshot SQLite no paso integrity_check.');
    }
  } finally {
    sqlite.close();
  }
}

Future<String> _sha256(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
