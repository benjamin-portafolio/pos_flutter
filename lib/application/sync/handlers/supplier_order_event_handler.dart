import '../supplier_intent.dart';
import '../payloads/supplier_receipt_confirmed_payload.dart';
import '../payloads/supplier_order_closed_payload.dart';
import '../models/sync_event.dart';
import '../supplier_order_operation.dart';
import '../projections/supplier_order_projection.dart';
import '../projections/supplier_order_projection_store.dart';

class SupplierOrderEventHandler {
  SupplierOrderEventHandler(this.store);
  final SupplierOrderProjectionStore store;
  Future<void> apply(SyncEvent event) async {
    final op = SupplierOrderOperation.decode(event);
    if (op.status == 'receipt' && await store.receiptApplied(event)) {
      if (event.serverSequence != null) {
        await store.acknowledge(op.orderId, event.serverSequence!);
      }
      await store.acknowledgeEffects(event);
      return;
    }
    final current = await store.find(op.orderId);
    if (current?.lastEventId == event.eventId) {
      final previous = await store.eventById(event.eventId);
      if (previous != null &&
          supplierIntent(previous.payload) != supplierIntent(event.payload)) {
        throw StateError('Identidad de evento reutilizada con otra intención.');
      }
      if (event.serverSequence != null) {
        await store.acknowledge(op.orderId, event.serverSequence!);
      }
      return;
    }
    if (op.baseEventId == null
        ? current != null
        : current == null ||
              current.lastEventId != op.baseEventId ||
              current.version != event.baseVersion ||
              (event.serverSequence == null &&
                  current.lastServerSequence != event.baseServerSequence)) {
      throw StateError(
        'El pedido cambió. Recupera la versión vigente y revisa tu intención.',
      );
    }
    if (op.status == 'receipt') {
      await store.receive(
        event,
        SupplierReceiptConfirmedPayload.fromJson(event.payload),
      );
      return;
    }
    if (op.status == 'closed') {
      await store.closeRemainder(
        event,
        SupplierOrderClosedPayload.fromJson(event.payload),
      );
      return;
    }
    if (current != null &&
        (current.status != 'draft' &&
            !(op.status == 'cancelled' && current.status == 'confirmed'))) {
      throw StateError('El estado del pedido no permite esta operación.');
    }
    if (op.status == 'cancelled' && await store.hasReceipts(op.orderId)) {
      throw StateError(
        'El pedido tiene recepciones; solo se podrá cerrar el remanente.',
      );
    }
    final doc = op.document ?? current!.document;
    if (current != null && current.document.supplierId != doc.supplierId) {
      throw StateError('Un pedido conserva su proveedor.');
    }
    if (op.status != 'cancelled') {
      await store.validateLineIdentities(event, doc.items);
      final catalog = await store.candidates();
      final eligible = {
        for (final c in catalog.where((c) => c.supplierId == doc.supplierId))
          c.variantId: c,
      };
      final oldItems = {
        for (final l in current?.document.items ?? doc.items) l.id: l.variantId,
      };
      for (final l in doc.items) {
        final c = eligible[l.variantId];
        if (oldItems.containsKey(l.id) && oldItems[l.id] != l.variantId) {
          throw StateError('Una partida no puede cambiar de variante.');
        }
        if (c == null ||
            c.inventoryItemId != l.inventoryItemId ||
            c.unitId != l.unitId ||
            c.dimension != l.dimension ||
            c.atomicFactor != l.unitAtomicFactor ||
            c.referenceAtomic != l.referenceQuantityAtomic) {
          throw StateError(
            'Cambió la disponibilidad, el recurso o la unidad de una partida.',
          );
        }
      }
    }
    await store.write(
      SupplierOrderProjection(
        document: doc,
        status: op.status,
        version: current == null ? 1 : current.version + 1,
        createdEventId: current?.createdEventId ?? event.eventId,
        lastEventId: event.eventId,
        lastServerSequence: event.serverSequence ?? current?.lastServerSequence,
      ),
    );
  }
}
