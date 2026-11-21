import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/caja/abrir_caja_command.dart';
import 'package:pos_flutter/application/commands/ventas/agregar_producto_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/confirmar_venta_command.dart';
import 'package:pos_flutter/application/config/app_config.dart';
import 'package:pos_flutter/application/recovery/recovery_cancellation.dart';
import 'package:pos_flutter/data/local/backup/database_restore_service.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'package:pos_flutter/data/local/recovery/drift_recovery_snapshot_source.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/supplier_order_harness.dart';
import '../../../application/commands/proveedores/supplier_receipt_local_test.dart'
    show confirmedOrder, receipt;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in AppMode.values) {
    test(
      'Recepción real: backup/restore por staging conserva conjunto y modo ${mode.name}',
      () async {
        final dir = await Directory.systemTemp.createTemp('receipt-backup-');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => dir.path,
            );
        final h = ProductSupplierHarness(database: AppDatabase(), mode: mode);
        try {
          final id = await confirmedOrder(h), c = await receipt(h, id, 3);
          await h.orders.receive(c);
          final variant = (await h.tracking.orders.find(
            id,
          ))!.document.items.single.variantId;
          await h.tracking.cash.abrir(
            AbrirCajaCommand(sessionId: const Uuid().v4(), openingMinor: 0),
          );
          for (var i = 0; i < 2; i++) {
            await h.tracking.drafts.agregar(
              AgregarProductoBorradorCommand(variantId: variant),
            );
          }
          final sale = (await h.db.select(h.db.sales).get()).singleWhere(
            (s) => s.status == 'borrador',
          );
          await h.tracking.sales.confirmar(
            ConfirmarVentaCommand(
              saleId: sale.id,
              expectedDraftEventId: sale.lastEventId!,
              expectedTotalMinor: sale.totalMinor,
            ),
          );
          final snapshot = await DriftRecoverySnapshotSource(h.db).capture(
            privateDirectory: Directory('${dir.path}/capture'),
            mode: mode,
            deviceId: h.tracking.context.deviceId,
            appRevision: 'supplier-S4',
            cancellation: RecoveryCancellation(),
          );
          final backup = await snapshot.file.copy('${dir.path}/backup.sqlite');
          snapshot.close();
          final tables = [
            'products',
            'product_variants',
            'suppliers',
            'variant_suppliers',
            'units',
            'sales',
            'sale_items',
            'sale_payments',
            'cash_sessions',
            'cash_movements',
            'supplier_orders',
            'supplier_order_items',
            'supplier_receipts',
            'supplier_receipt_items',
            'inventory_movements',
            'inventory_balances',
            'events',
            'event_refs',
          ];
          final before = {
            for (final t in tables)
              t:
                  (await h.db
                          .customSelect('SELECT * FROM $t ORDER BY rowid')
                          .get())
                      .map((r) => r.data)
                      .toList(),
          };
          await h.orders.receive(await receipt(h, id, 1));
          await DriftDatabaseRestoreService(db: h.db).restoreSnapshot(
            backup,
            sha256: sha256.convert(await backup.readAsBytes()).toString(),
          );
          final reopened = ProductSupplierHarness(
            database: AppDatabase(),
            mode: mode,
          );
          final restored = reopened.db;
          try {
            for (final t in tables) {
              expect(
                (await restored
                        .customSelect('SELECT * FROM $t ORDER BY rowid')
                        .get())
                    .map((r) => r.data)
                    .toList(),
                before[t],
                reason: t,
              );
            }
            expect(
              (await restored.select(restored.supplierOrders).get())
                  .single
                  .status,
              'partial',
            );
            expect(
              (await restored.select(restored.inventoryBalances).get())
                  .single
                  .quantityOnHandAtomic,
              4,
            );
            // The persisted receipt/event identity must survive staging and reopen.
            await reopened.orders.receive(c);
            for (final t in tables) {
              expect(
                (await restored
                        .customSelect('SELECT * FROM $t ORDER BY rowid')
                        .get())
                    .map((r) => r.data)
                    .toList(),
                before[t],
                reason: 'retry after restore: $t',
              );
            }
          } finally {
            await reopened.dispose();
          }
        } finally {
          await h.dispose();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('plugins.flutter.io/path_provider'),
                null,
              );
          await dir.delete(recursive: true);
        }
      },
    );
  }
}
