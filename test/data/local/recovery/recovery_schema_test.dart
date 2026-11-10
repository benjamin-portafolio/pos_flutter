import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/current_database_schema.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  test('physical v10', () async {
    final raw = sql.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    await db.customSelect('SELECT 1').get();
    expect(hasCurrentAppDatabaseSchema(raw), isTrue);
    await db.close();
  });
}
