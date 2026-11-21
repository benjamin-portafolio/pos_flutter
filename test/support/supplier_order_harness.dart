import 'package:uuid/uuid.dart';
import 'package:pos_flutter/application/commands/proveedores/supplier_order_command_service.dart';
import 'package:pos_flutter/application/commands/proveedores/save_supplier_order_command.dart';
import 'package:pos_flutter/application/sync/payloads/supplier_order_draft_saved_payload.dart';
import 'package:pos_flutter/presentation/pages/gestion_inventario/pedidos/supplier_order_forms.dart';
import 'product_supplier_harness.dart';

extension SupplierOrderHarness on ProductSupplierHarness {
  SupplierOrderCommandService get orders => SupplierOrderCommandService(
    store: tracking.orders,
    events: tracking.events,
    context: tracking.context,
    requireCompatible: () async {},
  );
  Future<SupplierOrderDraftSavedPayload> newOrder({
    String? supplierId,
    int? quantity,
  }) async {
    final rows = (await tracking.orders.candidates())
        .where((c) => supplierId == null || c.supplierId == supplierId)
        .toList();
    final c = rows.first;
    return orderDocument(
      id: const Uuid().v4(),
      base: null,
      supplierId: c.supplierId,
      name: c.supplierName,
      phone: c.supplierPhone,
      currency: 'MXN',
      occurredAtMs: DateTime.now().millisecondsSinceEpoch,
      items: [
        candidateLine(c, const Uuid().v4(), quantity ?? c.suggestedAtomic),
      ],
    );
  }

  Future<SaveSupplierOrderCommand> orderCommand(
    SupplierOrderDraftSavedPayload doc, {
    bool confirm = false,
    String? eventId,
  }) async => SaveSupplierOrderCommand(
    eventId: eventId ?? const Uuid().v4(),
    document: doc,
    confirm: confirm,
    catalogBasis: {
      for (final c in (await tracking.orders.candidates()).where(
        (c) => c.supplierId == doc.supplierId,
      ))
        c.variantId: c.basis,
    },
  );
  Future<SupplierOrderDraftSavedPayload> based(String id) async {
    final o = (await tracking.orders.find(id))!;
    return SupplierOrderDraftSavedPayload.fromJson({
      ...o.document.toJson(),
      'base_event_id': o.lastEventId,
    });
  }
}
