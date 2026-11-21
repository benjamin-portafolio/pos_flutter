import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/application/commands/proveedores/confirm_supplier_receipt_command.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_receipt_confirmed_payload.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/supplier_order_harness.dart';

void main() {
  for (final phase in ['before_commit', 'after_commit']) {
    test(
      'SIGKILL $phase: reapertura recupera cero o una aplicación y reintenta con identidad original',
      () async {
        final dir = await Directory.systemTemp.createTemp('receipt-sigkill-');
        try {
          final process = await Process.run(
            'flutter',
            [
              'test',
              '--no-pub',
              'test/support/supplier_receipt_crash_worker.dart',
            ],
            environment: {
              'POS_RECEIPT_CRASH_DIR': dir.path,
              'POS_RECEIPT_CRASH_PHASE': phase,
            },
          );
          expect(process.exitCode, isNot(0));
          expect(
            await File('${dir.path}/terminated').exists(),
            true,
            reason: '${process.stdout}\n${process.stderr}',
          );
          final h = ProductSupplierHarness(
            database: AppDatabase.forTesting(
              NativeDatabase(File('${dir.path}/db.sqlite')),
            ),
          );
          try {
            final j =
                jsonDecode(await File('${dir.path}/intent.json').readAsString())
                    as Map;
            final c = ConfirmSupplierReceiptCommand(
              eventId: j['event_id'] as String,
              payload: SupplierReceiptConfirmedPayload.fromJson(j['payload']),
            );
            expect(
              (await h.db.select(h.db.supplierReceipts).get()).length,
              phase == 'before_commit' ? 0 : 1,
            );
            await h.orders.receive(c);
            expect((await h.db.select(h.db.supplierReceipts).get()).length, 1);
            expect(
              (await h.db.select(h.db.inventoryBalances).get())
                  .single
                  .quantityOnHandAtomic,
              7,
            );
            expect(
              (await h.db.select(h.db.inventoryMovements).get())
                  .where((m) => m.eventId == c.eventId)
                  .length,
              1,
            );
          } finally {
            await h.dispose();
          }
        } finally {
          await dir.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
