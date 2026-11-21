import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_flutter/data/local/drift/app_database.dart';
import 'product_supplier_harness.dart';
import 'supplier_order_harness.dart';
import '../application/commands/proveedores/supplier_receipt_local_test.dart'
    show confirmedOrder, receipt;

void main() {
  test(
    'private worker: terminate process after receipt COMMIT without closing SQLite',
    () async {
      final root = Platform.environment['POS_RECEIPT_CRASH_DIR']!;
      final h = ProductSupplierHarness(
        database: AppDatabase.forTesting(
          NativeDatabase(File('$root/db.sqlite')),
        ),
      );
      final id = await confirmedOrder(h), c = await receipt(h, id, 4);
      await File('$root/intent.json').writeAsString(
        jsonEncode({'event_id': c.eventId, 'payload': c.payload.toJson()}),
        flush: true,
      );
      Future<void> terminate() async {
        await File('$root/terminated').writeAsString('ready', flush: true);
        Process.killPid(pid, ProcessSignal.sigkill);
      }

      if (Platform.environment['POS_RECEIPT_CRASH_PHASE'] == 'before_commit') {
        await h.tracking.events.runInTransaction(() async {
          await h.orders.receive(c);
          await terminate();
          await Future<void>.delayed(const Duration(seconds: 1));
        });
      } else {
        await h.orders.receive(c);
        await terminate();
      }
    },
  );
}
