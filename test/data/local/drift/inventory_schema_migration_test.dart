import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/development_database_reset.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  for (final version in [4, 5, 6, 7, 8]) {
    test(
      'esquema no acreditado versión $version conserva inventario e historia',
      () async {
        final dir = await Directory.systemTemp.createTemp('old-inventory-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/db');
        final db = sqlite.sqlite3.open(file.path);
        db.execute(
          'CREATE TABLE historical_inventory(id TEXT,quantity INTEGER,cost INTEGER)',
        );
        db.execute(
          "INSERT INTO historical_inventory VALUES ('original',17,123)",
        );
        db.execute('PRAGMA user_version=$version');
        db.close();
        final before = sha256.convert(await file.readAsBytes());
        await expectLater(
          resetDevelopmentDatabase(
            file,
            shouldPreserveRestoredDatabase: () async => false,
          ),
          throwsStateError,
        );
        expect(sha256.convert(await file.readAsBytes()), before);
        final read = sqlite.sqlite3.open(file.path);
        expect(
          read.select('SELECT * FROM historical_inventory').single['quantity'],
          17,
        );
        read.close();
      },
    );
  }
}
