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
    'rechaza esquema anterior no acreditado conservando todos sus datos',
    () async {
      final file = await appDatabaseFile();
      final old = sqlite.sqlite3.open(file.path);
      old.execute('CREATE TABLE obsolete_data (id TEXT)');
      old.execute("INSERT INTO obsolete_data VALUES ('keep')");
      old.execute('PRAGMA user_version = 7');
      old.close();
      final before = await file.readAsBytes();
      final db = AppDatabase();
      await expectLater(db.select(db.products).get(), throwsStateError);
      await expectLater(db.close(), throwsStateError);
      expect(await file.readAsBytes(), before);
    },
  );

  for (final restored in [false, true]) {
    test('esquema con is_default: respaldo restaurado=$restored', () async {
      final initial = AppDatabase();
      await initial.customStatement(
        'ALTER TABLE product_variants ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0',
      );
      await initial.customStatement("SELECT 1");
      await initial.close();
      if (restored) await markAppDatabaseAsRestored();

      final reopened = AppDatabase();
      {
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
