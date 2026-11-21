import 'dart:convert';
import '../../application/proveedores/supplier_order_reader.dart';
import '../../application/proveedores/supplier_order_detail.dart';
import '../../application/sync/payloads/supplier_receipt_confirmed_payload.dart';
import 'package:drift/drift.dart';
import '../../domain/proveedores/supplier_order_failed_attempt.dart';
import '../../domain/proveedores/replenishment_candidate.dart';
import '../../domain/proveedores/replenishment_issue.dart';
import '../../domain/proveedores/supplier_order_summary.dart';
import '../../domain/repositories/supplier_order_repository.dart';
import '../local/drift/app_database.dart';
import '../local/drift/drift_supplier_order_store.dart';

class DriftSupplierOrderRepository
    implements SupplierOrderRepository, SupplierOrderReader {
  DriftSupplierOrderRepository(this.db);
  final AppDatabase db;
  Set<TableInfo> get _tables => {
    db.products,
    db.productVariants,
    db.inventoryItems,
    db.inventoryBalances,
    db.units,
    db.suppliers,
    db.variantSuppliers,
    db.recipeComponents,
    db.supplierOrders,
    db.supplierOrderItems,
    db.supplierReceipts,
    db.supplierReceiptItems,
    db.events,
  };
  @override
  Stream<SupplierOrderDetail?> watchDetail(String id) => db
      .customSelect('SELECT 1', readsFrom: _tables)
      .watch()
      .asyncMap((_) => readDetail(id));

  @override
  Future<SupplierOrderDetail?> readDetail(
    String id,
  ) => db.transaction(() async {
    final order = await DriftSupplierOrderStore(db).find(id);
    if (order == null) return null;
    final rows = await db
        .customSelect(
          '''SELECT r.id,e.payload,e.delivery_status
      FROM supplier_receipts r JOIN events e ON e.event_id=r.event_id
      WHERE r.order_id=? ORDER BY e.local_sequence''',
          variables: [Variable(id)],
        )
        .get();
    final receipts = rows
        .map(
          (r) => SupplierReceiptConfirmedPayload.fromJson(
            jsonDecode(r.read<String>('payload')),
          ),
        )
        .toList();
    final lines = await (db.select(
      db.supplierOrderItems,
    )..where((l) => l.orderId.equals(id))).get();
    final balances = await db
        .customSelect(
          '''SELECT i.id,coalesce(b.quantity_on_hand_atomic,0) qty,
      i.last_event_id FROM inventory_items i LEFT JOIN inventory_balances b ON b.inventory_item_id=i.id
      WHERE i.id IN (SELECT inventory_item_id FROM supplier_order_items WHERE order_id=?) ORDER BY i.id''',
          variables: [Variable(id)],
        )
        .get();
    final event = await DriftSupplierOrderStore(
      db,
    ).eventById(order.lastEventId!);
    final failed =
        await (db.select(db.events)..where(
              (e) =>
                  e.aggregateType.equals('supplier_order') &
                  e.aggregateId.equals(id) &
                  e.deliveryStatus.isIn(['conflict', 'rejected']),
            ))
            .get();
    final catalog =
        (await DriftSupplierOrderStore(db).candidates())
            .where(
              (c) =>
                  c.supplierId == order.document.supplierId &&
                  order.document.items.any((l) => l.variantId == c.variantId),
            )
            .toList()
          ..sort((a, b) => a.variantId.compareTo(b.variantId));
    return SupplierOrderDetail(
      order: order,
      receipts: List.unmodifiable(receipts),
      failedReceipts: failed
          .where(
            (e) => e.eventType == SupplierReceiptConfirmedPayload.eventType,
          )
          .map(
            (e) =>
                SupplierReceiptConfirmedPayload.fromJson(jsonDecode(e.payload)),
          )
          .toList(),
      received: {
        for (final l in lines)
          l.id: receipts
              .expand((r) => r.items)
              .where((r) => r.orderItemId == l.id)
              .fold<int>(0, (v, r) => v + r.quantityAtomic),
      },
      closed: {for (final l in lines) l.id: l.closedQuantityAtomic},
      balances: {
        for (final b in balances) b.read<String>('id'): b.read<int>('qty'),
      },
      deliveryStatus: event?.deliveryStatus ?? 'delivered',
      receiptStatuses: {
        for (final r in rows)
          r.read<String>('id'): r.read<String>('delivery_status'),
      },
      failures: failed
          .map(
            (e) =>
                '${e.deliveryStatus}: ${e.rejectionReason ?? 'Revisa el intento rechazado'}',
          )
          .toList(),
      catalogBasis: {for (final c in catalog) c.variantId: c.basis},
      reviewBasis: jsonEncode([
        order.lastEventId!,
        order.lastServerSequence,
        for (final b in balances) b.data,
        for (final c in catalog) [c.variantId, c.basis],
      ]),
    );
  });
  @override
  Stream<List<ReplenishmentCandidate>> watchCandidates() => db
      .customSelect('SELECT 1', readsFrom: _tables)
      .watch()
      .asyncMap((_) => DriftSupplierOrderStore(db).candidates());
  @override
  Stream<List<ReplenishmentIssue>> watchIssues() => db
      .customSelect('''SELECT p.id product_id,v.id variant_id,
    p.name,CASE WHEN v.current_supplier_id IS NULL THEN 'Falta proveedor actual'
    WHEN v.target_stock_atomic IS NULL THEN 'Falta objetivo'
    WHEN s.active IS NOT 1 THEN 'Proveedor inactivo'
    WHEN vs.variant_id IS NULL THEN 'Falta cotización válida'
    ELSE 'Recurso o unidad no disponible' END reason
    FROM product_variants v JOIN products p ON p.id=v.product_id
    LEFT JOIN inventory_items i ON i.id=v.inventory_item_id LEFT JOIN units u ON u.unit_id=i.default_unit_id
    LEFT JOIN suppliers s ON s.id=v.current_supplier_id
    LEFT JOIN variant_suppliers vs ON vs.variant_id=v.id AND vs.supplier_id=v.current_supplier_id
    WHERE p.active=1 AND v.active=1 AND v.inventory_item_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM recipe_components rc WHERE rc.variant_id=v.id)
    AND (v.current_supplier_id IS NULL OR v.target_stock_atomic IS NULL OR s.active IS NOT 1 OR vs.variant_id IS NULL
      OR i.active IS NOT 1 OR u.active IS NOT 1
      OR (p.sale_mode='unit' AND u.dimension<>'count')
      OR (p.sale_mode='measured' AND (SELECT dimension FROM units su WHERE su.unit_id=p.sale_unit_id)<>u.dimension))
    ORDER BY p.name''', readsFrom: _tables)
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => ReplenishmentIssue(
                r.read<String>('product_id'),
                r.read<String>('variant_id'),
                r.read<String>('name'),
                r.read<String>('reason'),
              ),
            )
            .toList(),
      );
  @override
  Stream<List<SupplierOrderSummary>> watchOrders() => db
      .customSelect(
        '''WITH received AS (SELECT order_item_id,sum(quantity_atomic) qty FROM supplier_receipt_items GROUP BY order_item_id), overlapping AS (
    SELECT l.variant_id FROM supplier_order_items l JOIN supplier_orders o ON o.id=l.order_id
    LEFT JOIN received r ON r.order_item_id=l.id
    WHERE o.status IN ('confirmed','partial') AND l.quantity_atomic > l.closed_quantity_atomic + coalesce(r.qty,0)
    GROUP BY l.variant_id HAVING count(DISTINCT l.order_id)>1)
    SELECT o.*,e.delivery_status,e.rejection_reason,
      EXISTS(SELECT 1 FROM supplier_order_items l JOIN overlapping x ON x.variant_id=l.variant_id
        WHERE l.order_id=o.id) overlap
    FROM supplier_orders o LEFT JOIN events e ON e.event_id=o.last_event_id
    ORDER BY o.occurred_at_ms DESC''',
        readsFrom: _tables,
      )
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => SupplierOrderSummary(
                id: r.read<String>('id'),
                supplierId: r.read<String>('supplier_id'),
                supplierName: r.read<String>('supplier_name_snapshot'),
                status: r.read<String>('status'),
                occurredAtMs: r.read<int>('occurred_at_ms'),
                totalMinor: r.readNullable<int>('total_minor'),
                deliveryStatus:
                    r.readNullable<String>('delivery_status') ?? 'delivered',
                issue: r.readNullable<String>('rejection_reason'),
                overlaps:
                    r.read<int>('overlap') == 1 &&
                    ['confirmed', 'partial'].contains(r.read<String>('status')),
              ),
            )
            .toList(),
      );
  @override
  Stream<List<SupplierOrderFailedAttempt>> watchFailedAttempts() => db
      .customSelect(
        r'''SELECT e.event_id,e.aggregate_id,e.delivery_status,e.event_type,
    coalesce(e.rejection_reason,'La base del pedido cambió.') reason,
    coalesce(json_extract(e.payload,'$.supplier_name_snapshot'),o.supplier_name_snapshot,'Pedido') supplier_name FROM events e LEFT JOIN supplier_orders o ON o.id=e.aggregate_id
    WHERE e.aggregate_type='supplier_order' AND e.delivery_status IN ('conflict','rejected')
      AND e.event_type IN ('supplier_order_draft_saved','supplier_order_confirmed','supplier_receipt_confirmed','supplier_order_closed')
      AND NOT EXISTS(SELECT 1 FROM events newer WHERE newer.aggregate_type=e.aggregate_type AND newer.aggregate_id=e.aggregate_id
        AND newer.local_sequence>e.local_sequence AND newer.delivery_status IN ('conflict','rejected')
        AND newer.event_type IN ('supplier_order_draft_saved','supplier_order_confirmed','supplier_receipt_confirmed','supplier_order_closed'))
    ORDER BY e.local_sequence DESC''',
        readsFrom: {db.events},
      )
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => SupplierOrderFailedAttempt(
                eventId: r.read<String>('event_id'),
                canRecoverDraft: {
                  'supplier_order_draft_saved',
                  'supplier_order_confirmed',
                }.contains(r.read<String>('event_type')),
                orderId: r.read<String>('aggregate_id'),
                supplierName: r.read<String>('supplier_name'),
                reason: r.read<String>('reason'),
                status: r.read<String>('delivery_status'),
              ),
            )
            .toList(),
      );
}
