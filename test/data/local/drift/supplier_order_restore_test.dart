import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/application/recovery/recovery_diagnostic.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_snapshot_source.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in [AppMode.standalone, AppMode.serverSync]) {
    test('documentos: restricciones, backup y restore staging ($mode)', () async {
      final temp = await Directory.systemTemp.createTemp('supplier-restore-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path,
          );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        await temp.delete(recursive: true);
      });
      final db = AppDatabase();
      final unit = AppDatabase.inventoryUnitSeed.first.unitId;
      await db.customStatement(
        "INSERT INTO products(id,name) VALUES('p','Café')",
      );
      await db.customStatement(
        "INSERT INTO suppliers(id,name) VALUES('s','Proveedor')",
      );
      await db.customStatement(
        "INSERT INTO inventory_items(id,default_unit_id,name) VALUES('resource',?,'Café físico')",
        [unit],
      );
      await db.customStatement(
        "INSERT INTO product_variants(id,product_id,sale_price_minor,sort_order,inventory_item_id) VALUES('v','p',10,0,'resource')",
      );
      await db.customStatement(
        "INSERT INTO variant_suppliers VALUES('v','s',0,100)",
      );
      await db.customStatement(
        "UPDATE product_variants SET current_supplier_id='s',target_stock_atomic=7 WHERE id='v'",
      );
      await db.customStatement(
        "INSERT INTO inventory_balances(inventory_item_id,quantity_on_hand_atomic,quantity_available_atomic,last_event_id) VALUES('resource',3,3,'initial')",
      );
      await db.customStatement(
        "INSERT INTO supplier_orders(id,supplier_id,status,occurred_at_ms,currency,supplier_name_snapshot,total_minor) VALUES('o','s','confirmed',100,'MXN','Proveedor',0),('other','s','confirmed',100,'MXN','Proveedor',0)",
      );
      Future<void> line(int position, int quantity) => db.customStatement(
        "INSERT INTO supplier_order_items(id,order_id,variant_id,inventory_item_id,unit_id,product_name_snapshot,dimension,unit_code_snapshot,unit_symbol_snapshot,unit_atomic_factor,reference_quantity_atomic,quantity_atomic,quoted_price_minor,total_minor,position) VALUES('l','o','v','resource',?,'Café','count','piece','pza',1,1,?,0,0,?)",
        [unit, quantity, position],
      );
      await expectLater(line(50, 4), throwsA(isA<Exception>()));
      await expectLater(line(0, 0), throwsA(isA<Exception>()));
      await line(0, 4);
      expect(
        (await db.select(db.inventoryBalances).getSingle())
            .quantityOnHandAtomic,
        3,
      );
      await db.customStatement(
        "INSERT INTO supplier_receipts(id,order_id,event_id,intent_hash,base_event_id,occurred_at_ms,total_minor) VALUES('r','o','e',?,'base',100,0)",
        ['a' * 64],
      );
      await db.customStatement(
        "INSERT INTO inventory_movements(movement_id,inventory_item_id,event_id,movement_type,quantity_delta_atomic,created_at_local) VALUES('m','resource','e','entry',1,100)",
      );
      // Only physical fixtures; S1 never calls a receipt handler or updates balances.
      Future<void> receive(String order) => db.customStatement(
        "INSERT INTO supplier_receipt_items(id,receipt_id,order_id,order_item_id,quantity_atomic,actual_price_minor,total_minor,movement_id) VALUES('rl','r',?,'l',1,0,0,'m')",
        [order],
      );
      await expectLater(receive('other'), throwsA(isA<Exception>()));
      await receive('o');
      await expectLater(receive('o'), throwsA(isA<Exception>()));
      await expectLater(
        db.customStatement("DELETE FROM supplier_orders WHERE id='o'"),
        throwsA(isA<Exception>()),
      );
      final snapshot = await DriftRecoverySnapshotSource(db).capture(
        privateDirectory: Directory('${temp.path}/capture'),
        mode: mode,
        deviceId: 'fixture',
        appRevision: 'S1',
        cancellation: RecoveryCancellation(),
      );
      expect((snapshot.cut['source'] as Map)['schema_version'], 11);
      final diagnostic = await RecoveryDiagnostic.inspect(
        snapshot,
        RecoveryCancellation(),
      );
      expect(
        diagnostic.blockers.any(
          (b) => b['code'] == 'supplier_order_projection_mismatch',
        ),
        true,
      );
      expect(
        diagnostic.blockers.any(
          (b) =>
              b['code'] ==
              'supplier_replenishment_recovery_requires_contract_v2',
        ),
        false,
      );
      final backup = File('${temp.path}/backup.sqlite');
      await snapshot.file.copy(backup.path);
      snapshot.close();
      final hash = sha256.convert(await backup.readAsBytes()).toString();
      final before = sql.sqlite3.open(backup.path);
      final all = {
        for (final t in [
          'supplier_orders',
          'supplier_order_items',
          'supplier_receipts',
          'supplier_receipt_items',
          'product_variants',
          'inventory_balances',
          'inventory_movements',
        ])
          t: before
              .select('SELECT * FROM $t')
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
      };
      before.close();
      await db.customStatement("UPDATE products SET name='Cambio posterior'");
      await DriftDatabaseRestoreService(
        db: db,
      ).restoreSnapshot(backup, sha256: hash);
      expect(sha256.convert(await backup.readAsBytes()).toString(), hash);
      final restored = AppDatabase();
      for (final t in all.entries) {
        expect(
          (await restored.customSelect('SELECT * FROM ${t.key}').get())
              .map((r) => r.data)
              .toList(),
          t.value,
          reason: t.key,
        );
      }
      expect(
        (await restored.select(restored.products).getSingle()).name,
        'Café',
      );
      expect(
        (await restored.select(restored.inventoryBalances).getSingle())
            .quantityOnHandAtomic,
        3,
      );
      await restored.close();
    });
  }
}
