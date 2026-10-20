import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pos-draft-tabs-schema-');
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
    'arranque recrea el esquema de un borrador y conserva el nuevo entre reinicios',
    () async {
      final initial = AppDatabase();
      await initial.customSelect('SELECT id FROM sales').get();
      final version = initial.schemaVersion;
      await initial.close();
      final file = await appDatabaseFile();
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('DROP INDEX ix_sales_local_drafts');
      raw.execute(
        "CREATE UNIQUE INDEX ux_sales_local_draft ON sales(user_id, device_id) WHERE active = 1 AND status = 'borrador'",
      );
      raw.execute('CREATE TABLE obsolete_marker (id TEXT)');
      raw.close();

      final current = AppDatabase();
      expect(current.schemaVersion, version);
      expect(
        await current
            .customSelect(
              "SELECT 1 FROM sqlite_master WHERE name = 'obsolete_marker'",
            )
            .get(),
        isEmpty,
      );
      expect(
        await current
            .customSelect(
              "SELECT 1 FROM sqlite_master WHERE name = 'ux_sales_local_draft'",
            )
            .get(),
        isEmpty,
      );
      expect(
        await current
            .customSelect(
              "SELECT 1 FROM sqlite_master WHERE name = 'ix_sales_local_drafts'",
            )
            .get(),
        hasLength(1),
      );
      for (final id in ['one', 'two']) {
        await current.customStatement(
          'INSERT INTO sales(id, user_id, device_id, total_minor, created_at_local, updated_at_local) VALUES (?, ?, ?, 0, 1, 1)',
          [id, 'user', 'device'],
        );
      }
      await current.close();
      final reopened = AppDatabase();
      expect(
        (await reopened.select(reopened.sales).get())
            .map((sale) => sale.id)
            .toSet(),
        {'one', 'two'},
      );
      await reopened.close();
    },
  );
}
