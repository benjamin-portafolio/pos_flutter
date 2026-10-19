import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/current_database_schema.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Future<void> seed(AppDatabase db) async {
  await db
      .into(db.products)
      .insert(ProductsCompanion.insert(id: 'p', name: 'Café'));
  await db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          id: 'v',
          productId: 'p',
          salePriceMinor: 1000,
          sortOrder: 0,
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('rango SQL real y Drift', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await seed(db);
    });
    tearDown(() => db.close());
    test(
      'null, cero, medido y máximo; copias y serialización generadas',
      () async {
        for (final value in [null, 0, 1500, 9007199254740991]) {
          await (db.update(
            db.productVariants,
          )..where((v) => v.id.equals('v'))).write(
            ProductVariantsCompanion(minimumStockAtomic: Value(value)),
          );
          final row = await db.select(db.productVariants).getSingle();
          expect(row.minimumStockAtomic, value);
          expect(
            ProductVariantRow.fromJson(row.toJson()).minimumStockAtomic,
            value,
          );
          expect(row.copyWith().minimumStockAtomic, value);
        }
        expect(await db.select(db.inventoryMovements).get(), isEmpty);
        expect(db.schemaVersion, 8);
      },
    );
    for (final value in <Object>[-1, 9007199254740992, 1.5, 'inválido']) {
      test('CHECK rechaza $value sin alterar fila', () async {
        await expectLater(
          db.customStatement(
            'UPDATE product_variants SET minimum_stock_atomic = ? WHERE id = ?',
            [value, 'v'],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        expect(
          (await db.select(db.productVariants).getSingle()).minimumStockAtomic,
          isNull,
        );
      });
    }
  });
  group('arranque y restore aislados', () {
    late Directory temp;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('pos_minimum_stock_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path,
          );
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await temp.delete(recursive: true);
    });
    for (final protected in [false, true]) {
      test('base sin columna actual; protegida=$protected', () async {
        final initial = AppDatabase();
        await seed(initial);
        await initial.customStatement(
          'ALTER TABLE product_variants RENAME COLUMN minimum_stock_atomic TO old_threshold',
        );
        await initial.close();
        final file = await appDatabaseFile();
        final raw = sqlite.sqlite3.open(file.path);
        expect(hasCurrentAppDatabaseSchema(raw), isFalse);
        raw.close();
        if (protected) await markAppDatabaseAsRestored();
        final hash = sha256.convert(await file.readAsBytes()).toString();
        final reopened = AppDatabase();
        if (protected) {
          await expectLater(
            reopened.select(reopened.products).get(),
            throwsStateError,
          );
          await expectLater(reopened.close(), throwsStateError);
          expect(sha256.convert(await file.readAsBytes()).toString(), hash);
        } else {
          expect(await reopened.select(reopened.products).get(), isEmpty);
          expect(
            (await reopened
                    .customSelect('PRAGMA table_info(product_variants)')
                    .get())
                .map((r) => r.data['name']),
            contains('minimum_stock_atomic'),
          );
          expect(reopened.schemaVersion, 8);
          await reopened.close();
        }
      });
    }
    test(
      'restore rechaza esquema sin columna antes de reemplazar datos',
      () async {
        final db = AppDatabase();
        await seed(db);
        await db.customStatement(
          'UPDATE product_variants SET minimum_stock_atomic = 1500',
        );
        final snapshot = await DriftDatabaseSnapshotService(
          db: db,
          stateReader: DriftDatabaseStateReader(db: db),
        ).createSnapshot();
        try {
          final raw = sqlite.sqlite3.open(snapshot.file.path);
          raw.execute(
            'ALTER TABLE product_variants RENAME COLUMN minimum_stock_atomic TO old_threshold',
          );
          raw.close();
          final hash = sha256
              .convert(await snapshot.file.readAsBytes())
              .toString();
          await expectLater(
            DriftDatabaseRestoreService(
              db: db,
            ).restoreSnapshot(snapshot.file, sha256: hash),
            throwsStateError,
          );
          expect(
            (await db.select(db.productVariants).getSingle())
                .minimumStockAtomic,
            1500,
          );
          expect(await appDatabaseShouldPreserveRestoredDatabase(), isFalse);
        } finally {
          await db.close();
          await snapshot.file.parent.delete(recursive: true);
        }
      },
    );
    test(
      'nuevo esquema conserva mínimo tras reopen, snapshot y restore',
      () async {
        var db = AppDatabase();
        await seed(db);
        await db.customStatement(
          'UPDATE product_variants SET minimum_stock_atomic = 1500',
        );
        await db.close();
        db = AppDatabase();
        expect(
          (await db.select(db.productVariants).getSingle()).minimumStockAtomic,
          1500,
        );
        final snapshot = await DriftDatabaseSnapshotService(
          db: db,
          stateReader: DriftDatabaseStateReader(db: db),
        ).createSnapshot();
        try {
          await db.customStatement(
            'UPDATE product_variants SET minimum_stock_atomic = NULL',
          );
          await DriftDatabaseRestoreService(
            db: db,
          ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
          db = AppDatabase();
          expect(
            (await db.select(db.productVariants).getSingle())
                .minimumStockAtomic,
            1500,
          );
          expect(
            await db.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
          expect(
            (await db.customSelect('PRAGMA integrity_check').get())
                .single
                .data
                .values
                .single,
            'ok',
          );
        } finally {
          await db.close();
          await snapshot.file.parent.delete(recursive: true);
        }
      },
    );
  });
}
