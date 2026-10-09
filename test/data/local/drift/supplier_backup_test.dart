import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/database_snapshot_service.dart';
import 'package:pos_flutter/data/local/backup/database_state_reader.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pos_suppliers_test_');
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
            salePriceMinor: 2500,
            sortOrder: 0,
          ),
        );
    await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: 's',
            name: 'Norte',
            phone: const Value('00123'),
            notes: const Value('Semanal'),
            createdEventId: const Value('e'),
            lastEventId: const Value('e'),
          ),
        );
    await db
        .into(db.variantSuppliers)
        .insert(
          VariantSuppliersCompanion.insert(
            variantId: 'v',
            supplierId: 's',
            quotedPriceMinor: 0,
            quotedAtMs: 1791331200000,
          ),
        );
    await db.customStatement(
      'CREATE TABLE retained_supplier_marker(value TEXT)',
    );
  }

  Future<List<Map<String, Object?>>> contents(AppDatabase db) async => [
    for (final row in await db.customSelect('SELECT * FROM suppliers').get())
      row.data,
    for (final row
        in await db.customSelect('SELECT * FROM variant_suppliers').get())
      row.data,
  ];
  test(
    'arranques y snapshot/restore preservan proveedores y precio cero',
    () async {
      var db = AppDatabase();
      await seed(db);
      final before = await contents(db);
      await db.close();
      db = AppDatabase();
      expect(await contents(db), before);
      final snapshot = await DriftDatabaseSnapshotService(
        db: db,
        stateReader: DriftDatabaseStateReader(db: db),
      ).createSnapshot();
      try {
        await db.delete(db.variantSuppliers).go();
        await db.delete(db.suppliers).go();
        await DriftDatabaseRestoreService(
          db: db,
        ).restoreSnapshot(snapshot.file, sha256: snapshot.sha256);
        db = AppDatabase();
        expect(await contents(db), before);
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
        await db.close();
        db = AppDatabase();
        expect(await contents(db), before);
        expect(
          await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE name='retained_supplier_marker'",
              )
              .get(),
          hasLength(1),
        );
        expect(await appDatabaseShouldPreserveRestoredDatabase(), isTrue);
        expect(db.schemaVersion, 8);
      } finally {
        await db.close();
        await snapshot.file.parent.delete(recursive: true);
      }
    },
  );
  for (final protected in [false, true]) {
    for (final missing in ['tables', 'supplier-column', 'relation-column']) {
      test('detección esquema sin $missing, protegido=$protected', () async {
        final db = AppDatabase();
        await seed(db);
        if (missing == 'tables') {
          await db.customStatement('DROP TABLE variant_suppliers');
          await db.customStatement('DROP TABLE suppliers');
        } else if (missing == 'supplier-column') {
          await db.customStatement('ALTER TABLE suppliers DROP COLUMN notes');
        } else {
          await db.customStatement(
            'ALTER TABLE variant_suppliers RENAME COLUMN quoted_at_ms TO legacy_quoted_at_ms',
          );
        }
        await db.close();
        final file = await appDatabaseFile();
        if (protected) await markAppDatabaseAsRestored();
        final beforeHash = sha256.convert(await file.readAsBytes()).toString();
        final reopened = AppDatabase();
        if (protected) {
          await expectLater(
            reopened.select(reopened.suppliers).get(),
            throwsStateError,
          );
          await expectLater(reopened.close(), throwsStateError);
          expect(
            sha256.convert(await file.readAsBytes()).toString(),
            beforeHash,
          );
        } else {
          expect(await reopened.select(reopened.suppliers).get(), isEmpty);
          expect(
            await reopened.select(reopened.variantSuppliers).get(),
            isEmpty,
          );
          expect(
            await reopened
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE name='retained_supplier_marker'",
                )
                .get(),
            isEmpty,
          );
          expect(reopened.schemaVersion, 8);
          await reopened.close();
        }
      });
    }
  }
  for (final invalid in ['old-schema', 'orphan']) {
    test(
      'restore rechaza $invalid antes de reemplazar la base actual',
      () async {
        final db = AppDatabase();
        await seed(db);
        final before = await contents(db);
        final snapshot = await DriftDatabaseSnapshotService(
          db: db,
          stateReader: DriftDatabaseStateReader(db: db),
        ).createSnapshot();
        try {
          final raw = sqlite.sqlite3.open(snapshot.file.path);
          try {
            if (invalid == 'old-schema') {
              raw.execute('DROP TABLE variant_suppliers');
              raw.execute('DROP TABLE suppliers');
            } else {
              raw.execute("UPDATE variant_suppliers SET supplier_id='unknown'");
            }
          } finally {
            raw.close();
          }
          final hash = sha256
              .convert(await snapshot.file.readAsBytes())
              .toString();
          await expectLater(
            DriftDatabaseRestoreService(
              db: db,
            ).restoreSnapshot(snapshot.file, sha256: hash),
            throwsStateError,
          );
          expect(await contents(db), before);
          expect(await appDatabaseShouldPreserveRestoredDatabase(), isFalse);
        } finally {
          await db.close();
          await snapshot.file.parent.delete(recursive: true);
        }
      },
    );
  }
}
