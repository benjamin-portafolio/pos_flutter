import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos_financial_schema_');
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

  test('esquema actual crea tablas financieras con restricciones e índices y conserva datos entre arranques', () async {
    final db = AppDatabase();
    final tables = (await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('financial_categories', 'financial_entries') ORDER BY name",
            )
            .get())
        .map((row) => row.read<String>('name'));
    expect(tables, ['financial_categories', 'financial_entries']);

    final columns = (await db
            .customSelect('PRAGMA table_info(financial_entries)')
            .get())
        .map((row) => row.read<String>('name'));
    expect(
      columns,
      containsAll(['category_id', 'category_name_snapshot', 'amount_minor', 'currency', 'occurred_at_ms', 'notes', 'reference']),
    );

    final indexRows = (await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND name IN ('ix_financial_entries_period', 'ix_financial_entries_category') ORDER BY name",
            )
            .get())
        .map((row) => row.read<String>('name'));
    expect(indexRows, ['ix_financial_entries_category', 'ix_financial_entries_period']);

    final fks = (await db.customSelect('PRAGMA foreign_key_list(financial_entries)').get())
        .map((row) => row.data)
        .toList();
    expect(
      fks.any((row) => row['table'] == 'financial_categories' && row['on_delete'] == 'RESTRICT'),
      isTrue,
    );

    await db.customStatement(
      "INSERT INTO financial_categories(id,name,direction,nature) VALUES('11111111-1111-4111-8111-111111111111','Renta','out','operating')",
    );
    await db.customStatement(
      "INSERT INTO financial_entries(id,category_id,category_name_snapshot,direction,nature,amount_minor,currency,method,occurred_at_ms,notes,reference) VALUES('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111','Renta','out','operating',50000,'MXN','cash',1789041600000,'Renta de septiembre',NULL)",
    );
    await db.customStatement("CREATE TABLE retained_marker (id TEXT)");
    await db.customStatement("INSERT INTO retained_marker VALUES ('keep')");

    final invalid = <String>[
      "INSERT INTO financial_categories(id,name,direction,nature) VALUES('a2','x','bad','operating')",
      "INSERT INTO financial_categories(id,name,direction,nature) VALUES('a3','x','in','asset_purchase')",
      "INSERT INTO financial_entries(id,category_id,category_name_snapshot,direction,nature,amount_minor,currency,method,occurred_at_ms) VALUES('b2','11111111-1111-4111-8111-111111111111','Renta','out','operating',0,'MXN','cash',1)",
      "INSERT INTO financial_entries(id,category_id,category_name_snapshot,direction,nature,amount_minor,currency,method,occurred_at_ms) VALUES('b3','11111111-1111-4111-8111-111111111111','Renta','out','operating',50000,'USD','cash',1)",
    ];
    for (final sql in invalid) {
      await expectLater(db.customStatement(sql), throwsA(anything));
    }
    await expectLater(
      db.customStatement(
        "DELETE FROM financial_categories WHERE id = '11111111-1111-4111-8111-111111111111'",
      ),
      throwsA(anything),
    );
    await db.close();

    final reopened = AppDatabase();
    expect(
      (await reopened.customSelect('SELECT id FROM retained_marker').get()).single
          .read<String>('id'),
      'keep',
    );
    expect(
      (await reopened.customSelect('SELECT amount_minor FROM financial_entries').get())
          .single
          .read<int>('amount_minor'),
      50000,
    );
    await reopened.close();
  });

  test('base anterior sin tablas financieras se recrea y crea el nuevo esquema', () async {
    final file = await appDatabaseFile();
    final old = sqlite.sqlite3.open(file.path);
    old.execute('CREATE TABLE obsolete_data (id TEXT)');
    old.close();

    final db = AppDatabase();
    expect(
      await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name = 'obsolete_data'",
          )
          .get(),
      isEmpty,
    );
    final tables = (await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('financial_categories', 'financial_entries') ORDER BY name",
            )
            .get())
        .map((row) => row.read<String>('name'));
    expect(tables, ['financial_categories', 'financial_entries']);
    expect(db.schemaVersion, 7);
    await db.close();
  });

  test('respaldo restaurado anterior sin tablas financieras no se destruye', () async {
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

  test('respaldo restaurado con esquema actual se conserva', () async {
    final initial = AppDatabase();
    await initial.customStatement("CREATE TABLE retained_marker (id TEXT)");
    await initial.customStatement("INSERT INTO retained_marker VALUES ('keep')");
    await initial.close();
    await markAppDatabaseAsRestored();

    final reopened = AppDatabase();
    expect(
      (await reopened.customSelect('SELECT id FROM retained_marker').get()).single
          .read<String>('id'),
      'keep',
    );
    final tables = (await reopened
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('financial_categories', 'financial_entries') ORDER BY name",
            )
            .get())
        .map((row) => row.read<String>('name'));
    expect(tables, ['financial_categories', 'financial_entries']);
    await reopened.close();
  });
}