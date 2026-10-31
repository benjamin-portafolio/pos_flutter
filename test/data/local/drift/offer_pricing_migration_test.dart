import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/drift/current_database_schema.dart';
import 'package:pos_flutter/data/local/drift/offer_pricing_schema.dart';
import 'package:pos_flutter/data/local/drift/recognized_schema_v8.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/backup/safe_database_replacement.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void seedV8(File file) {
  final db = sql.sqlite3.open(file.path);
  for (final ddl in recognizedSchemaV8Sql) {
    db.execute(ddl);
  }
  db.execute('PRAGMA user_version=8');
  db.execute(
    "INSERT INTO products(id,name,created_event_id,last_event_id,last_server_sequence) VALUES ('p','Café','e','e',42)",
  );
  db.execute(
    "INSERT INTO product_variants(id,product_id,sale_price_minor,standard_cost_minor,sort_order,minimum_stock_atomic) VALUES ('v','p',2500,0,0,10)",
  );
  db.execute(
    "INSERT INTO sales(id,user_id,device_id,status,total_minor,created_at_local,updated_at_local) VALUES ('s','u','d','confirmada',5000,100,101),('draft','u','d','borrador',2500,100,101)",
  );
  db.execute(
    "INSERT INTO sale_items(id,sale_id,variant_id,product_name_snapshot,sale_mode_snapshot,quantity,unit_price_minor,standard_cost_minor_snapshot,total_minor,sort_order) VALUES ('l','s','v','Café','unit',2,2500,123,5000,0),('dl','draft','v','Café','unit',1,2500,0,2500,0)",
  );
  db.execute(
    "INSERT INTO sale_payments(id,sale_id,amount_minor,received_minor,change_minor,currency) VALUES ('pay','s',5000,6000,1000,'MXN')",
  );
  db.execute(
    "INSERT INTO events(event_id,aggregate_type,aggregate_id,event_type,device_id,user_id,server_sequence,created_at_local,payload,delivery_status) VALUES ('e','product','p','producto_creado','d','u',42,100,'{\"untouched\":true}','delivered')",
  );
  db.execute(
    "INSERT INTO sync_checkpoints(checkpoint_id,last_full_pull_server_sequence,last_preflight_server_sequence,last_full_pull_at,last_preflight_at) VALUES ('server',42,55,123,124)",
  );
  db.execute(
    "INSERT INTO product_update_undo(event_id,product_id,snapshot_json,memory_json) VALUES ('pending','p','{\"before\":true}','[]')",
  );
  db.execute(
    "INSERT INTO bulk_edit_operations(operation_id,batch_id,product_id,mode,intent_json,local_state,confirmed_at) VALUES ('operation','batch','p','server_sync','{}','confirmada',123)",
  );
  db.execute(
    "INSERT INTO event_refs(event_ref_id,event_id,ref_type,ref_id,relationship,source,server_sequence) VALUES ('ref','e','product','p','affects','local',42)",
  );
  db.execute(
    "INSERT INTO units(unit_id,code,name,symbol,dimension,atomic_factor,max_fraction_digits) VALUES ('unit','pza','Pieza','pza','count',1,0)",
  );
  db.execute(
    "INSERT INTO inventory_items(id,default_unit_id,name) VALUES ('resource','unit','Café físico')",
  );
  db.execute(
    "INSERT INTO inventory_balances(inventory_item_id,quantity_on_hand_atomic,quantity_available_atomic,last_event_id,last_server_sequence) VALUES ('resource',17,16,'e',42)",
  );
  db.execute(
    "INSERT INTO inventory_movements(movement_id,inventory_item_id,event_id,movement_type,quantity_delta_atomic,created_at_local) VALUES ('mov','resource','e','initial_balance',17,100)",
  );
  db.execute(
    "INSERT INTO account_balance_baselines(id,device_id,declared_by_user_id,amount_minor,as_of_ms) VALUES ('baseline','d','u',12345,100)",
  );
  db.execute(
    "INSERT INTO variant_inventory_memory(variant_id,inventory_item_id,source_event_id,source_server_sequence) VALUES ('v','resource','e',42)",
  );
  db.execute(
    "INSERT INTO clientes(id,nombre) VALUES ('customer','Cliente histórico')",
  );
  db.execute(
    "INSERT INTO sales(id,user_id,device_id,status,total_minor,cliente_id,created_at_local,updated_at_local) VALUES ('credit-sale','u','d','confirmada',7000,'customer',100,101)",
  );
  db.execute(
    "INSERT INTO credit_sales(id,sale_id,cliente_id,amount_minor,occurred_at_ms) VALUES ('credit-sale','credit-sale','customer',7000,100)",
  );
  db.execute(
    "INSERT INTO customer_payments(id,cliente_id,amount_minor,method,occurred_at_ms) VALUES ('customer-payment','customer',2000,'transfer',102)",
  );
  db.execute(
    "INSERT INTO credit_allocations(payment_id,credit_id,amount_minor) VALUES ('customer-payment','credit-sale',2000)",
  );
  db.close();
}

Map<String, List<Map<String, Object?>>> snapshot(File f) {
  final db = sql.sqlite3.open(f.path);
  try {
    return {
      for (final r in db.select(
        "SELECT name FROM sqlite_master WHERE type='table'",
      ))
        r['name'] as String: db
            .select('SELECT * FROM "${r['name']}"')
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
    };
  } finally {
    db.close();
  }
}

String hash(File f) => sha256.convert(f.readAsBytesSync()).toString();
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late File file;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('offer-migration-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
    file = await appDatabaseFile();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temp.delete(recursive: true);
  });
  test(
    'v8 físico completo -> v9: conserva todas las filas y segunda apertura',
    () async {
      seedV8(file);
      final before = snapshot(file);
      await prepareAppDatabase(file);
      final after = snapshot(file);
      for (final table in before.keys) {
        expect(
          after[table]!
              .map(
                (r) => Map.fromEntries(
                  r.entries.where(
                    (e) =>
                        !(offerPricingColumns[table]?.containsKey(e.key) ??
                            false),
                  ),
                ),
              )
              .toList(),
          before[table],
          reason: table,
        );
      }
      final db = sql.sqlite3.open(file.path);
      expect(hasCurrentAppDatabaseSchema(db), isTrue);
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      db.close();
      final h = hash(file);
      await prepareAppDatabase(file);
      expect(hash(file), h);
      final drift = AppDatabase();
      expect(
        (await drift.select(drift.saleItems).get())
            .first
            .standardCostMinorSnapshot,
        123,
      );
      expect(
        (await drift.select(drift.productVariants).getSingle()).offerPriceMinor,
        isNull,
      );
      await drift.close();
    },
  );
  test(
    'arranque real migra v8 y segunda apertura conserva crédito y todas las columnas previas',
    () async {
      seedV8(file);
      final originalHash = hash(file);
      final before = snapshot(file);
      for (var opening = 0; opening < 2; opening++) {
        final db = AppDatabase();
        try {
          // No llamar prepareAppDatabase: se ejercita LazyDatabase de producción.
          expect(
            (await db.select(db.creditSales).getSingle()).amountMinor,
            7000,
          );
          expect(
            (await db.select(db.creditAllocations).getSingle()).amountMinor,
            2000,
          );
          final after = snapshot(file);
          for (final table in before.keys) {
            expect(
              after[table]!
                  .map(
                    (row) => Map.fromEntries(
                      row.entries.where(
                        (e) =>
                            !(offerPricingColumns[table]?.containsKey(e.key) ??
                                false),
                      ),
                    ),
                  )
                  .toList(),
              before[table],
              reason: '$opening/$table',
            );
          }
          expect(
            (await db.select(db.events).getSingle()).payload,
            '{"untouched":true}',
          );
          expect(
            (await db.select(db.syncCheckpoints).getSingle())
                .lastFullPullServerSequence,
            42,
          );
        } finally {
          await db.close();
        }
      }
      expect(
        hash(file),
        isNot(originalHash),
        reason: 'Cambios aditivos de esquema esperados',
      );
    },
  );
  test('arranque real rechaza huella desconocida sin perder archivo', () async {
    seedV8(file);
    final raw = sql.sqlite3.open(file.path);
    raw.execute('ALTER TABLE sales ADD COLUMN unknown TEXT');
    raw.close();
    final original = hash(file);
    final db = AppDatabase();
    try {
      await expectLater(db.customSelect('SELECT 1').get(), throwsStateError);
      expect(hash(file), original);
    } finally {
      // LazyDatabase.close propaga el mismo error de apertura fallida.
      await expectLater(db.close(), throwsStateError);
    }
    expect(hash(file), original);
  });
  test(
    'fallo tras ALTER revierte DDL, datos y versión; después reintenta',
    () async {
      seedV8(file);
      final before = snapshot(file);
      await expectLater(
        prepareAppDatabase(
          file,
          afterAlterForTesting: (_) => throw StateError('injected'),
        ),
        throwsStateError,
      );
      expect(snapshot(file), before);
      final db = sql.sqlite3.open(file.path);
      expect(db.select('PRAGMA user_version').single.values.single, 8);
      db.close();
      await prepareAppDatabase(file);
    },
  );
  test(
    'muerte del proceso tras ALTER revierte transacción al reabrir',
    () async {
      seedV8(file);
      final before = snapshot(file);
      final child = await Process.run('dart', [
        'run',
        'test/support/offer_migration_crash.dart',
        file.path,
      ]);
      expect(child.exitCode, 73, reason: '${child.stdout} ${child.stderr}');
      expect(snapshot(file), before);
      final raw = sql.sqlite3.open(file.path);
      expect(raw.select('PRAGMA user_version').single.values.single, 8);
      raw.close();
      await prepareAppDatabase(file);
    },
  );
  test(
    'v8 reconocida con datos confirmados todavía en WAL conserva esos valores',
    () async {
      seedV8(file);
      final raw = sql.sqlite3.open(file.path);
      try {
        raw.execute('PRAGMA journal_mode=WAL');
        raw.execute('PRAGMA wal_autocheckpoint=0');
        raw.execute("UPDATE products SET name='Confirmado en WAL'");
        expect(await File('${file.path}-wal').length(), greaterThan(0));
        final before = snapshot(file);
        await prepareAppDatabase(file);
        final after = snapshot(file);
        for (final table in before.keys) {
          expect(
            after[table]!
                .map(
                  (r) => Map.fromEntries(
                    r.entries.where(
                      (e) =>
                          !(offerPricingColumns[table]?.containsKey(e.key) ??
                              false),
                    ),
                  ),
                )
                .toList(),
            before[table],
            reason: table,
          );
        }
        expect(
          raw.select('SELECT name FROM products').single['name'],
          'Confirmado en WAL',
        );
        expect(raw.select('PRAGMA user_version').single.values.single, 9);
      } finally {
        raw.close();
      }
      await prepareAppDatabase(file);
    },
  );
  test('esquema desconocido conserva archivo, WAL y SHM', () async {
    seedV8(file);
    final db = sql.sqlite3.open(file.path);
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA wal_autocheckpoint=0');
    db.execute('ALTER TABLE sales ADD COLUMN unknown TEXT');
    final hashes = {
      for (final suffix in ['', '-wal', '-shm'])
        suffix: hash(File('${file.path}$suffix')),
    };
    await expectLater(prepareAppDatabase(file), throwsStateError);
    for (final entry in hashes.entries) {
      expect(
        hash(File('${file.path}${entry.key}')),
        entry.value,
        reason: entry.key,
      );
    }
    db.close();
  });
  test(
    'restore de v8 migra staging sin cambiar original y abre dos veces',
    () async {
      final source = File('${temp.path}/legacy.sqlite');
      seedV8(source);
      final h = hash(source);
      final before = snapshot(source);
      var db = AppDatabase();
      await db.customSelect('SELECT 1').get();
      await DriftDatabaseRestoreService(
        db: db,
      ).restoreSnapshot(source, sha256: h);
      expect(hash(source), h);
      for (var i = 0; i < 2; i++) {
        db = AppDatabase();
        expect(
          (await db.select(db.salePayments).getSingle()).amountMinor,
          5000,
        );
        expect(
          (await db.select(db.events).getSingle()).payload,
          '{"untouched":true}',
        );
        await db.close();
        final after = snapshot(file);
        for (final table in before.keys) {
          expect(
            after[table]!
                .map(
                  (row) => Map.fromEntries(
                    row.entries.where(
                      (e) =>
                          !(offerPricingColumns[table]?.containsKey(e.key) ??
                              false),
                    ),
                  ),
                )
                .toList(),
            before[table],
            reason: 'restore/$i/$table',
          );
        }
      }
    },
  );
  test('restore inválido o hash erróneo conserva destino utilizable', () async {
    final db = AppDatabase();
    await db.customSelect('SELECT 1').get();
    final bad = File('${temp.path}/unknown');
    seedV8(bad);
    final raw = sql.sqlite3.open(bad.path);
    raw.execute('ALTER TABLE sales ADD COLUMN unknown TEXT');
    raw.close();
    for (final digest in ['wrong', hash(bad)]) {
      await expectLater(
        DriftDatabaseRestoreService(
          db: db,
        ).restoreSnapshot(bad, sha256: digest),
        throwsStateError,
      );
      expect(await db.select(db.sales).get(), isEmpty);
    }
    await db.close();
  });
  test(
    'fallo y recuperación por diario conservan última base válida',
    () async {
      seedV8(file);
      final h = hash(file);
      final staged = File('${temp.path}/stage');
      seedV8(staged);
      await expectLater(
        replaceDatabaseSafely(
          file,
          staged,
          markRestored: () async {},
          afterBackupForTesting: () async => throw StateError('injected'),
        ),
        throwsStateError,
      );
      expect(hash(file), h);
      final backup = await Directory('${temp.path}/interrupted').create();
      await file.rename('${backup.path}/database');
      await File('${file.path}.restore-journal').writeAsString(
        jsonEncode({
          'backup': backup.path,
          'original': [''],
        }),
      );
      await recoverDatabaseReplacement(file);
      expect(hash(file), h);
    },
  );
  test('esquema nuevo exige oferta <= normal y snapshot v2 completo', () async {
    final db = AppDatabase();
    await db.customStatement(
      "INSERT INTO products(id,name) VALUES ('p','Café')",
    );
    await db.customStatement(
      "INSERT INTO product_variants(id,product_id,sale_price_minor,sort_order) VALUES ('v','p',2500,0)",
    );
    await db.customStatement(
      'UPDATE product_variants SET offer_price_minor=2000',
    );
    await expectLater(
      db.customStatement('UPDATE product_variants SET sale_price_minor=1500'),
      throwsA(anything),
    );
    await db.customStatement(
      "INSERT INTO sales(id,user_id,device_id,total_minor,created_at_local,updated_at_local) VALUES ('d','u','d',0,1,1)",
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO sale_items(id,sale_id,variant_id,product_name_snapshot,sale_mode_snapshot,quantity,unit_price_minor,total_minor,sort_order,price_snapshot_version) VALUES ('l','d','v','Café','unit',1,2000,2000,0,2)",
      ),
      throwsA(anything),
    );
    await db.close();
  });
}
