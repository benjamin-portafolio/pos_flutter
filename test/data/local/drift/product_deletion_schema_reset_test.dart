import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_deletion_schema_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test(
    'recrea esquema anterior una vez y conserva datos en el siguiente arranque',
    () async {
      final file = await appDatabaseFile();
      final old = sqlite.sqlite3.open(file.path);
      old.execute('CREATE TABLE obsolete_data (id TEXT)');
      old.execute('PRAGMA user_version = 7');
      old.close();
      var db = AppDatabase();
      expect(await db.select(db.productUpdateUndo).get(), isEmpty);
      expect(
        await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE name = 'obsolete_data'",
            )
            .get(),
        isEmpty,
      );
      await db.customStatement("CREATE TABLE retained_marker (id TEXT)");
      await db.customStatement("INSERT INTO retained_marker VALUES ('keep')");
      await db.close();
      db = AppDatabase();
      expect(
        (await db.customSelect('SELECT id FROM retained_marker').get()).single
            .read<String>('id'),
        'keep',
      );
      await db.close();
    },
  );

  test('no destruye un respaldo restaurado con esquema anterior', () async {
    final file = await appDatabaseFile();
    final old = sqlite.sqlite3.open(file.path);
    old.execute('CREATE TABLE obsolete_data (id TEXT)');
    old.close();
    await markAppDatabaseAsRestored();
    final db = AppDatabase();
    await expectLater(db.select(db.productUpdateUndo).get(), throwsStateError);
    await expectLater(db.close(), throwsStateError);
    final preserved = sqlite.sqlite3.open(file.path);
    expect(
      preserved.select(
        "SELECT name FROM sqlite_master WHERE name = 'obsolete_data'",
      ),
      hasLength(1),
    );
    preserved.close();
  });
}
