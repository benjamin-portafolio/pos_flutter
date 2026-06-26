import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pos_flutter/data/local/drift/tables/espacios.dart';
import 'package:pos_flutter/data/local/drift/tables/events.dart';
import 'package:pos_flutter/data/local/drift/tables/event_refs.dart';
import 'package:pos_flutter/domain/espacios/visibilidad_espacio.dart';

part 'app_database.g.dart';
part 'daos/espacio_dao.dart';
part 'daos/event_dao.dart';
part 'daos/event_ref_dao.dart';

/// Database class configuring connection, schema and registered tables/DAOs.
@DriftDatabase(
  tables: [Espacios, Events, EventRefs],
  daos: [EspacioDao, EventDao, EventRefDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // We added events and eventRefs tables in schema version 2
        await m.createTable(events);
        await m.createTable(eventRefs);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'pos_db.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
