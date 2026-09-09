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

  for (final restored in [false, true]) {
    test('esquema con is_default: respaldo restaurado=$restored', () async {
      final initial = AppDatabase();
      await initial.customStatement(
        'ALTER TABLE product_variants ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0',
      );
      await initial.customStatement('CREATE TABLE retained_marker (id TEXT)');
      await initial.close();
      if (restored) await markAppDatabaseAsRestored();

      final reopened = AppDatabase();
      if (restored) {
        await expectLater(
          reopened.select(reopened.products).get(),
          throwsStateError,
        );
        await expectLater(reopened.close(), throwsStateError);
        final preserved = sqlite.sqlite3.open((await appDatabaseFile()).path);
        try {
          expect(
            preserved
                .select('PRAGMA table_info(product_variants)')
                .map((column) => column['name']),
            contains('is_default'),
          );
        } finally {
          preserved.close();
        }
      } else {
        final columns = await reopened
            .customSelect('PRAGMA table_info(product_variants)')
            .get();
        expect(
          columns.map((column) => column.read<String>('name')),
          isNot(contains('is_default')),
        );
        expect(
          await reopened
              .customSelect(
                "SELECT name FROM sqlite_master WHERE name = 'retained_marker'",
              )
              .get(),
          isEmpty,
        );
        expect(reopened.schemaVersion, 7);
        await reopened.close();
      }
    });
  }

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
