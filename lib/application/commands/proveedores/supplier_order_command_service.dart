import '../../sync/supplier_intent.dart';
import 'confirm_supplier_receipt_command.dart';
import 'close_supplier_order_command.dart';
import '../../sync/payloads/supplier_receipt_confirmed_payload.dart';
import '../../sync/payloads/supplier_order_closed_payload.dart';
import 'recover_supplier_order_command.dart';
import '../../sync/supplier_order_operation.dart';
import '../../sync/payloads/supplier_order_line.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/supplier_order_draft_saved_payload.dart';
import '../../sync/payloads/supplier_order_confirmed_payload.dart';
import '../../sync/payloads/supplier_order_cancelled_payload.dart';
import '../../sync/projections/supplier_order_projection_store.dart';
import '../local_command_context.dart';
import 'save_supplier_order_command.dart';
import 'cancel_supplier_order_command.dart';

class SupplierOrderCommandService {
  SupplierOrderCommandService({
    required this.store,
    required this.events,
    required this.context,
    required this.requireCompatible,
    this.requireReceiptsCompatible,
  });
  final SupplierOrderProjectionStore store;
  final LocalEventStore events;
  final LocalCommandContext context;
  final Future<void> Function() requireCompatible;
  final Future<void> Function()? requireReceiptsCompatible;
  Future<void> recover(RecoverSupplierOrderCommand command) async {
    final source = await store.eventById(command.sourceEventId);
    if (source == null ||
        !['conflict', 'rejected'].contains(source.deliveryStatus)) {
      throw StateError('El intento no está en conflicto o rechazado.');
    }
    final doc = SupplierOrderOperation.decode(source).document;
    if (doc == null || command.orderId == doc.orderId) {
      throw StateError(
        'La recuperación requiere otro borrador con identidad nueva.',
      );
    }
    final recovered = SupplierOrderDraftSavedPayload.fromJson({
      ...doc.toJson(),
      'order_id': command.orderId,
      'base_event_id': null,
      'occurred_at_ms': command.occurredAtMs,
      'items': doc.items
          .map(
            (l) => SupplierOrderLine.fromJson({
              ...l.toJson(),
              'id': command.itemIds[l.id],
            }).toJson(),
          )
          .toList(),
    });
    await save(
      SaveSupplierOrderCommand(
        eventId: command.eventId,
        document: recovered,
        catalogBasis: const {},
      ),
    );
  }

  Future<void> save(SaveSupplierOrderCommand command) =>
      _atomic(() => _save(command));
  Future<void> _save(SaveSupplierOrderCommand command) async {
    await requireCompatible();
    final doc = command.document;
    final type = command.confirm
        ? SupplierOrderConfirmedPayload.eventType
        : SupplierOrderDraftSavedPayload.eventType;
    final payload = command.confirm
        ? SupplierOrderConfirmedPayload.fromJson(doc.toJson()).toJson()
        : doc.toJson();
    if (await _alreadyApplied(command.eventId, type, doc.orderId, payload)) {
      return;
    }
    final current = await store.find(doc.orderId);
    if (current?.lastEventId != doc.baseEventId) {
      throw StateError('El pedido cambió; revisa la base.');
    }
    final catalog = await store.candidates();
    final refs = <LocalEventRef>[
      LocalEventRef.affects(refType: 'supplier_order', refId: doc.orderId),
      LocalEventRef.uses(refType: 'supplier', refId: doc.supplierId),
    ];
    for (final line in doc.items) {
      final matches = catalog.where(
        (c) => c.variantId == line.variantId && c.supplierId == doc.supplierId,
      );
      if (matches.isEmpty) throw StateError('La partida dejó de ser elegible.');
      final c = matches.single;
      if (command.confirm && command.catalogBasis[line.variantId] != c.basis) {
        throw StateError(
          'Cambió el catálogo, saldo, pendiente o cotización. Revisa la base antes de confirmar.',
        );
      }
      refs.addAll([
        LocalEventRef.uses(refType: 'product', refId: c.productId),
        LocalEventRef.uses(refType: 'product_variant', refId: c.variantId),
        LocalEventRef.uses(refType: 'inventory_item', refId: c.inventoryItemId),
        LocalEventRef.uses(refType: 'unit', refId: c.unitId),
      ]);
    }
    await events.appendAndApply(
      SyncEvent(
        eventId: command.eventId,
        aggregateType: 'supplier_order',
        aggregateId: doc.orderId,
        eventType: type,
        deviceId: context.deviceId,
        userId: context.userId,
        baseVersion: current?.version ?? 1,
        baseServerSequence: current?.lastServerSequence,
        createdAtLocal: DateTime.fromMillisecondsSinceEpoch(
          doc.occurredAtMs,
          isUtc: true,
        ),
        payload: payload,
      ),
      refs: _unique(refs),
    );
  }

  Future<void> cancel(CancelSupplierOrderCommand command) =>
      _atomic(() => _cancel(command));
  Future<void> _cancel(CancelSupplierOrderCommand command) async {
    await requireCompatible();
    final payload = SupplierOrderCancelledPayload.fromJson({
      'contract_version': 1,
      'order_id': command.orderId,
      'base_event_id': command.baseEventId,
      'occurred_at_ms': command.occurredAtMs,
    });
    if (await _alreadyApplied(
      command.eventId,
      SupplierOrderCancelledPayload.eventType,
      command.orderId,
      payload.toJson(),
    )) {
      return;
    }
    final current = await store.find(command.orderId);
    if (current == null || current.lastEventId != command.baseEventId) {
      throw StateError('El pedido cambió; revisa la base.');
    }
    await events.appendAndApply(
      SyncEvent(
        eventId: command.eventId,
        aggregateType: 'supplier_order',
        aggregateId: command.orderId,
        eventType: SupplierOrderCancelledPayload.eventType,
        deviceId: context.deviceId,
        userId: context.userId,
        baseVersion: current.version,
        baseServerSequence: current.lastServerSequence,
        createdAtLocal: DateTime.fromMillisecondsSinceEpoch(
          command.occurredAtMs,
          isUtc: true,
        ),
        payload: payload.toJson(),
      ),
      refs: [
        LocalEventRef.affects(
          refType: 'supplier_order',
          refId: command.orderId,
        ),
        LocalEventRef.uses(
          refType: 'supplier',
          refId: current.document.supplierId,
        ),
      ],
    );
  }

  Future<void> receive(ConfirmSupplierReceiptCommand command) =>
      _atomic(() async {
        final p = command.payload;
        await _fulfil(
          command.eventId,
          p.orderId,
          p.baseEventId,
          p.occurredAtMs,
          SupplierReceiptConfirmedPayload.eventType,
          p.toJson(),
          catalogBasis: command.catalogBasis,
        );
      });

  Future<void> closeRemainder(CloseSupplierOrderCommand command) =>
      _atomic(() async {
        final p = command.payload;
        await _fulfil(
          command.eventId,
          p.orderId,
          p.baseEventId,
          p.occurredAtMs,
          SupplierOrderClosedPayload.eventType,
          p.toJson(),
        );
      });

  Future<void> _fulfil(
    String eventId,
    String id,
    String baseId,
    int time,
    String type,
    Map<String, Object?> payload, {
    Map<String, String>? catalogBasis,
  }) async {
    if (await _alreadyApplied(eventId, type, id, payload)) return;
    await (requireReceiptsCompatible ?? requireCompatible)();
    final current = await store.find(id);
    if (current == null || current.lastEventId != baseId) {
      throw StateError('El pedido cambió; revisa la base.');
    }
    final refs = <LocalEventRef>[
      LocalEventRef.affects(refType: 'supplier_order', refId: id),
      LocalEventRef.uses(
        refType: 'supplier',
        refId: current.document.supplierId,
      ),
    ];
    if (type == SupplierReceiptConfirmedPayload.eventType) {
      final p = SupplierReceiptConfirmedPayload.fromJson(payload);
      refs.add(
        LocalEventRef.affects(refType: 'supplier_receipt', refId: p.receiptId),
      );
      final catalog = await store.candidates();
      for (final received in p.items) {
        final line = current.document.items
            .where((l) => l.id == received.orderItemId)
            .single;
        final c = catalog
            .where(
              (c) =>
                  c.variantId == line.variantId &&
                  c.supplierId == current.document.supplierId,
            )
            .single;
        if (catalogBasis != null && catalogBasis[line.variantId] != c.basis) {
          throw StateError(
            'Cambió el catálogo, saldo o pendiente. Conserva la captura y revisa nuevamente.',
          );
        }
        refs.addAll([
          LocalEventRef.uses(refType: 'product', refId: c.productId),
          LocalEventRef.uses(refType: 'product_variant', refId: line.variantId),
          LocalEventRef.uses(refType: 'unit', refId: line.unitId),
          LocalEventRef.affects(
            refType: 'inventory_item',
            refId: line.inventoryItemId,
          ),
          LocalEventRef.affects(
            refType: 'inventory_movement',
            refId: received.movementId,
          ),
        ]);
      }
    }
    await events.appendAndApply(
      SyncEvent(
        eventId: eventId,
        aggregateType: 'supplier_order',
        aggregateId: id,
        eventType: type,
        deviceId: context.deviceId,
        userId: context.userId,
        baseVersion: current.version,
        baseServerSequence: current.lastServerSequence,
        createdAtLocal: DateTime.fromMillisecondsSinceEpoch(time, isUtc: true),
        payload: payload,
      ),
      refs: _unique(refs),
    );
  }

  Future<bool> _alreadyApplied(
    String id,
    String type,
    String orderId,
    Map<String, Object?> payload,
  ) async {
    final previous = await store.eventById(id);
    if (previous == null) return false;
    if (previous.eventType != type ||
        previous.aggregateId != orderId ||
        supplierIntent(previous.payload) != supplierIntent(payload)) {
      throw StateError('Identidad reutilizada con otra intención.');
    }
    if (previous.deliveryStatus == 'rejected' ||
        previous.deliveryStatus == 'conflict') {
      throw StateError(
        previous.rejectionReason ?? 'El intento anterior fue rechazado.',
      );
    }
    return true;
  }

  Future<void> _atomic(Future<void> Function() action) {
    final e = events;
    if (e is! LocalTransactionalEventStore) {
      throw StateError('Pedidos requiere un almacén transaccional.');
    }
    return (e as LocalTransactionalEventStore).runInTransaction(action);
  }

  List<LocalEventRef> _unique(List<LocalEventRef> refs) => {
    for (final r in refs) '${r.refType}:${r.refId}:${r.relationship}': r,
  }.values.toList();
}
