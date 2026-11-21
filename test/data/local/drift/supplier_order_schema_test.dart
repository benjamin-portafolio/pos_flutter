import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/recovery/recovery_json.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/current_database_schema.dart';
import 'package:pos_flutter/data/local/drift/offer_pricing_schema.dart';
import 'package:pos_flutter/data/local/drift/recognized_schema_v10.dart';
import 'package:pos_flutter/data/local/drift/recovery_revision_schema.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'offer_pricing_migration_test.dart' as legacy;

void main() {
  final signatures = <String, String>{};
  for (final mode in ['not_required', 'pending']) {
    for (final source in ['v8', 'v9', 'v10_migrated', 'v10_fresh']) {
      test('$source -> v11 conserva todas las columnas anteriores ($mode)', () async {
        final dir = await Directory.systemTemp.createTemp('supplier-s1-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/db.sqlite');
        legacy.seedV8(file);
        var raw = sql.sqlite3.open(file.path);
        raw.execute('UPDATE events SET delivery_status=?', [mode]);
        if (mode == 'not_required') raw.execute('DELETE FROM event_refs');
        raw.close();
        if (source == 'v10_fresh') {
          final data = legacy.snapshot(file);
          file.deleteSync();
          raw = sql.sqlite3.open(file.path);
          for (final ddl in [
            ...recognizedFreshV10Sql,
            ...offerPricingTriggers,
            ...recoveryRevisionTriggers,
          ]) {
            raw.execute(ddl);
          }
          // Fixture from accredited v8 rows inserted into accredited fresh v10 DDL.
          for (final table in data.entries) {
            for (final row in table.value) {
              raw.execute(
                'INSERT INTO "${table.key}" (${row.keys.join(',')}) VALUES (${row.keys.map((_) => '?').join(',')})',
                row.values.toList(),
              );
            }
          }
          raw.execute('INSERT INTO recovery_local_state(singleton) VALUES(1)');
          raw.execute('PRAGMA user_version=10');
          raw.close();
        } else if (source != 'v8') {
          raw = sql.sqlite3.open(file.path);
          for (final t in offerPricingColumns.entries) {
            for (final c in t.value.entries) {
              raw.execute(
                'ALTER TABLE ${t.key} ADD COLUMN ${c.key} ${c.value}',
              );
            }
          }
          for (final ddl in offerPricingTriggers) {
            raw.execute(ddl);
          }
          if (source == 'v10_migrated') {
            raw.execute(recoveryStateDdl);
            raw.execute(
              'INSERT INTO recovery_local_state(singleton) VALUES(1)',
            );
            for (final ddl in recoveryRevisionTriggers) {
              raw.execute(ddl);
            }
          }
          raw.execute('PRAGMA user_version=${source == 'v9' ? 9 : 10}');
          raw.close();
        }
        final before = legacy.snapshot(file);
        await expectLater(
          prepareAppDatabase(
            file,
            afterAlterForTesting: (_) => throw StateError('injected'),
          ),
          throwsStateError,
        );
        expect(legacy.snapshot(file), before);
        await prepareAppDatabase(file);
        final after = legacy.snapshot(file);
        for (final t in before.entries) {
          expect(
            after[t.key]!
                .map(
                  (r) => {
                    for (final k in t.value.firstOrNull?.keys ?? <String>[])
                      k: r[k],
                  },
                )
                .toList(),
            t.value,
            reason: t.key,
          );
        }
        raw = sql.sqlite3.open(file.path);
        expect(hasCurrentAppDatabaseSchema(raw), true);
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
        expect(raw.select('PRAGMA integrity_check').single.values.single, 'ok');
        expect(
          raw
              .select(
                'SELECT current_supplier_id,target_stock_atomic FROM product_variants',
              )
              .single
              .values,
          everyElement(isNull),
        );
        expect(raw.select('SELECT * FROM supplier_orders'), isEmpty);
        expect(
          raw
              .select('SELECT delivery_status FROM events')
              .single['delivery_status'],
          mode,
        );
        expect(
          raw.select('SELECT count(*) AS n FROM event_refs').single['n'],
          mode == 'not_required' ? 0 : 1,
        );
        signatures[source] = _physicalSignature(raw);
        raw.close();
        final hash = legacy.hash(file);
        await prepareAppDatabase(file);
        expect(legacy.hash(file), hash);
        final drift = AppDatabase.forTesting(NativeDatabase(file));
        expect(
          (await drift.select(drift.productVariants).getSingle())
              .targetStockAtomic,
          isNull,
        );
        await drift.close();
      });
    }
  }
  test('creación Drift, pertenencia y reemplazo DAO transaccional', () async {
    final raw = sql.sqlite3.openInMemory();
    final db = AppDatabase.forTesting(NativeDatabase.opened(raw));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();
    expect(hasCurrentAppDatabaseSchema(raw), true);
    signatures['v11_fresh'] = _physicalSignature(raw);
    await db.customStatement(
      "INSERT INTO products(id,name) VALUES('p','Café')",
    );
    await db.customStatement(
      "INSERT INTO suppliers(id,name) VALUES('s','Proveedor'),('s2','Otro')",
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO product_variants(id,product_id,sale_price_minor,sort_order,current_supplier_id) VALUES('v','p',10,0,'s')",
      ),
      throwsA(isA<Exception>()),
    );
    await db.transaction(() async {
      await db.customStatement(
        "INSERT INTO product_variants(id,product_id,sale_price_minor,sort_order) VALUES('v','p',10,0)",
      );
      await db.customStatement(
        "INSERT INTO variant_suppliers VALUES('v','s',10,100)",
      );
      await db.customStatement(
        "UPDATE product_variants SET current_supplier_id='s',target_stock_atomic=0 WHERE id='v'",
      );
    });
    await expectLater(
      db.customStatement("DELETE FROM variant_suppliers WHERE variant_id='v'"),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      db.customStatement(
        "UPDATE variant_suppliers SET supplier_id='s2' WHERE variant_id='v'",
      ),
      throwsA(isA<Exception>()),
    );
    await db.productoDao.reemplazarProveedoresVariante('v', [
      const VariantSuppliersCompanion(
        variantId: Value('v'),
        supplierId: Value('s'),
        quotedPriceMinor: Value(0),
        quotedAtMs: Value(101),
      ),
    ]);
    expect(
      (await db.select(db.productVariants).getSingle()).currentSupplierId,
      's',
    );
    await expectLater(
      db.productoDao.reemplazarProveedoresVariante('v', []),
      throwsStateError,
    );
    // Duplicate relation failure occurs after selection clearing/deletion; transaction restores all.
    const same = VariantSuppliersCompanion(
      variantId: Value('v'),
      supplierId: Value('s'),
      quotedPriceMinor: Value(50),
      quotedAtMs: Value(101),
    );
    await expectLater(
      db.productoDao.reemplazarProveedoresVariante('v', [same, same]),
      throwsA(isA<Exception>()),
    );
    expect(
      (await db.select(db.productVariants).getSingle()).currentSupplierId,
      's',
    );
    expect(
      (await db.select(db.variantSuppliers).getSingle()).quotedPriceMinor,
      0,
    );
    for (final n in [-1, 9007199254740992, 1.5, 'invalid']) {
      await expectLater(
        db.customStatement(
          'UPDATE product_variants SET target_stock_atomic=?',
          [n],
        ),
        throwsA(isA<Exception>()),
      );
    }
    await db.transaction(() async {
      await db.customStatement(
        "UPDATE product_variants SET current_supplier_id=NULL WHERE id='v'",
      );
      await db.customStatement(
        "DELETE FROM variant_suppliers WHERE variant_id='v'",
      );
      await db.customStatement(
        "INSERT INTO variant_suppliers VALUES('v','s2',0,100)",
      );
      await db.customStatement(
        "UPDATE product_variants SET current_supplier_id='s2' WHERE id='v'",
      );
    });
    expect(
      (await db.select(db.productVariants).getSingle()).currentSupplierId,
      's2',
    );
  });
  test('firmas físicas acreditadas para receptor de recuperación', () async {
    final out = File('/tmp/supplier-s1-source-fingerprints.json');
    await out.writeAsString(
      const JsonEncoder.withIndent('  ').convert(signatures),
    );
    expect(
      signatures.keys,
      containsAll(['v8', 'v9', 'v10_migrated', 'v10_fresh', 'v11_fresh']),
    );
  });
}

String _physicalSignature(sql.Database db) {
  final ddl = db
      .select(
        "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type,name",
      )
      .map((r) => Map<String, Object?>.from(r))
      .toList();
  return sha256.convert(utf8.encode(recoveryCanonical(ddl))).toString();
}
