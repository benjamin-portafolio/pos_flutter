import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/proveedores/confirm_supplier_receipt_command.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_receipt_input_line.dart';
import 'package:pos_flutter/data/repositories/drift_supplier_order_repository.dart';
import '../../../support/product_supplier_harness.dart';
import '../../../support/supplier_order_harness.dart';
import 'supplier_receipt_local_test.dart' show confirmedOrder;

void main() {
  test(
    'S5 revisión atómica: cambio de saldo después de leer bloquea; reintento aplicado ignora base consumida',
    () async {
      final h = ProductSupplierHarness();
      try {
        final id = await confirmedOrder(h);
        final reader = DriftSupplierOrderRepository(h.db);
        final initial = (await reader.readDetail(id))!;
        final l = initial.order.document.items.single;
        ConfirmSupplierReceiptCommand capture(Map<String, String> basis) =>
            ConfirmSupplierReceiptCommand.capture(
              eventId: const Uuid().v4(),
              orderId: id,
              baseEventId: initial.order.lastEventId!,
              receiptId: const Uuid().v4(),
              occurredAtMs: 600,
              items: [
                SupplierReceiptInputLine(
                  orderItemId: l.id,
                  movementId: const Uuid().v4(),
                  quantityAtomic: 4,
                  actualPriceMinor: 100,
                  referenceQuantityAtomic: l.referenceQuantityAtomic,
                ),
              ],
              catalogBasis: basis,
            );
        final stale = capture(initial.catalogBasis);
        // Deterministic change in the gap between UI read and writer transaction.
        await h.db.customUpdate(
          'UPDATE inventory_balances SET quantity_on_hand_atomic=1,quantity_available_atomic=1',
        );
        await expectLater(h.orders.receive(stale), throwsStateError);
        expect(await h.db.select(h.db.supplierReceipts).get(), isEmpty);
        final current = (await reader.readDetail(id))!;
        final command = capture(current.catalogBasis);
        await h.orders.receive(command);
        await h.orders.receive(command);
        expect(
          (await h.db.select(h.db.inventoryBalances).get())
              .single
              .quantityOnHandAtomic,
          5,
        );
        expect((await h.db.select(h.db.supplierReceipts).get()).length, 1);
      } finally {
        await h.dispose();
      }
    },
  );
}
