import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pos_flutter/data/local/drift/tables/espacios.dart';
import 'package:pos_flutter/data/local/drift/tables/events.dart';
import 'package:pos_flutter/data/local/drift/tables/event_refs.dart';
import 'package:pos_flutter/data/local/drift/tables/sync_checkpoints.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';

part 'app_database.g.dart';
part 'daos/espacio_dao.dart';
part 'daos/event_dao.dart';
part 'daos/event_ref_dao.dart';
part 'daos/sync_checkpoint_dao.dart';

const _resetDatabaseOnStartup = true;

/// Database class configuring connection, schema and registered tables/DAOs.
@DriftDatabase(
  tables: [Espacios, Events, EventRefs, SyncCheckpoints],
  daos: [EspacioDao, EventDao, EventRefDao, SyncCheckpointDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  // Drift requires a schema version. Keep it fixed during development and use
  // _resetDatabaseOnStartup when the local schema changes.
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'pos_db.sqlite'));

    if (kDebugMode && _resetDatabaseOnStartup) {
      await _deleteDatabaseFiles(file);
    }

    return NativeDatabase.createInBackground(file);
  });
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
