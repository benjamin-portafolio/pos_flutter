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
    'arranque rechaza índice no acreditado de borrador sin borrar datos',
    () async {
      final initial = AppDatabase();
      await initial.customSelect('SELECT id FROM sales').get();
      await initial.close();
      final file = await appDatabaseFile();
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute('DROP INDEX ix_sales_local_drafts');
      raw.execute(
        "CREATE UNIQUE INDEX ux_sales_local_draft ON sales(user_id, device_id) WHERE active = 1 AND status = 'borrador'",
      );
      raw.close();
      final before = await file.readAsBytes();
      final current = AppDatabase();
      await expectLater(current.select(current.sales).get(), throwsStateError);
      await expectLater(current.close(), throwsStateError);
      expect(await file.readAsBytes(), before);
    },
  );
}
