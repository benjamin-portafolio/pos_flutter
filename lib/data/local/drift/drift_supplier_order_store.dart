import '../../../application/sync/payloads/supplier_order_line.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../../application/sync/payloads/supplier_receipt_confirmed_payload.dart';
import '../../../application/sync/payloads/supplier_order_closed_payload.dart';
import '../../../application/sync/supplier_intent.dart';
import 'package:drift/drift.dart';
import '../../../application/sync/models/sync_event.dart';
import '../../../application/sync/projections/supplier_order_projection.dart';
import '../../../application/sync/projections/supplier_order_projection_store.dart';
import '../../../application/sync/payloads/supplier_order_draft_saved_payload.dart';
import '../../../application/sync/supplier_order_operation.dart';
import '../../../domain/proveedores/replenishment_candidate.dart';
import 'app_database.dart';
import 'drift_sync_persistence.dart';

class DriftSupplierOrderStore implements SupplierOrderProjectionStore {
  DriftSupplierOrderStore(this.db);
  final AppDatabase db;
  Future<List<QueryRow>> _quantities(String id) => db
      .customSelect(
        '''
    SELECT l.*, coalesce((SELECT sum(r.quantity_atomic) FROM supplier_receipt_items r
      WHERE r.order_item_id=l.id),0) received FROM supplier_order_items l WHERE l.order_id=?''',
        variables: [Variable(id)],
      )
      .get();

  Future<String> _receiptStatus(String id) async =>
      (await _quantities(
        id,
      )).every((l) => l.read<int>('received') >= l.read<int>('quantity_atomic'))
      ? 'received'
      : 'partial';

  Future<void> _advanceHead(SyncEvent e, String status) async {
    await db.customUpdate(
      '''UPDATE supplier_orders SET status=?,version=version+1,
      last_event_id=?,last_server_sequence=coalesce(?,last_server_sequence) WHERE id=?''',
      variables: [
        Variable(status),
        Variable(e.eventId),
        Variable<int>(e.serverSequence),
        Variable(e.aggregateId),
      ],
      updates: {db.supplierOrders},
    );
  }

  Future<void> _restoreHead(SupplierOrderProjection p) async {
    await db.customUpdate(
      '''UPDATE supplier_orders SET status=?,version=?,last_event_id=?,
      last_server_sequence=? WHERE id=?''',
      variables: [
        Variable(p.status),
        Variable(p.version),
        Variable(p.lastEventId),
        Variable<int>(p.lastServerSequence),
        Variable(p.id),
      ],
      updates: {db.supplierOrders},
    );
  }

  @override
  Future<bool> receiptApplied(SyncEvent e) async {
    final p = SupplierReceiptConfirmedPayload.fromJson(e.payload);
    final row = await (db.select(
      db.supplierReceipts,
    )..where((r) => r.id.equals(p.receiptId))).getSingleOrNull();
    if (row == null) return false;
    if (row.eventId != e.eventId ||
        row.intentHash !=
            sha256
                .convert(utf8.encode(supplierIntent(p.toJson())))
                .toString()) {
      throw StateError(
        'Identidad de recepción reutilizada con otra intención.',
      );
    }
    return true;
  }

  @override
  Future<void> receive(
    SyncEvent e,
    SupplierReceiptConfirmedPayload p,
  ) => db.transaction(() async {
    final hash = sha256
        .convert(utf8.encode(supplierIntent(p.toJson())))
        .toString();
    final existing = await (db.select(
      db.supplierReceipts,
    )..where((t) => t.id.equals(p.receiptId))).getSingleOrNull();
    if (existing != null) {
      if (existing.eventId != e.eventId || existing.intentHash != hash) {
        throw StateError('Identidad de recepción ocupada con otra intención.');
      }
      await acknowledgeEffects(e);
      return;
    }
    final current = (await find(p.orderId))!;
    if (!{'confirmed', 'partial'}.contains(current.status)) {
      throw StateError('El pedido no admite más recepciones.');
    }
    final amounts = {
      for (final q in await _quantities(p.orderId)) q.read<String>('id'): q,
    };
    final catalog = await candidates();
    // Validate every line before any effect; the surrounding event transaction also
    // protects document + ledger + balance against a later storage failure.
    for (final l in p.items) {
      final q = amounts[l.orderItemId];
      if (q == null || q.read<int>('closed_quantity_atomic') != 0) {
        throw StateError('Partida ajena o faltante cerrado.');
      }
      final original = current.document.items.singleWhere(
        (o) => o.id == l.orderItemId,
      );
      final matches = catalog.where(
        (c) =>
            c.variantId == original.variantId &&
            c.supplierId == current.document.supplierId,
      );
      if (matches.isEmpty) {
        throw StateError('La partida dejó de estar activa o vinculada.');
      }
      final c = matches.single;
      if (c.inventoryItemId != original.inventoryItemId ||
          c.unitId != original.unitId ||
          c.dimension != original.dimension ||
          c.atomicFactor != original.unitAtomicFactor ||
          c.referenceAtomic != original.referenceQuantityAtomic ||
          l.referenceQuantityAtomic != original.referenceQuantityAtomic) {
        throw StateError(
          'Cambió el recurso, unidad o dimensión de la partida.',
        );
      }
      if (BigInt.from(q.read<int>('received')) + BigInt.from(l.quantityAtomic) >
          BigInt.from(9007199254740991)) {
        throw StateError('Acumulado fuera de rango.');
      }
      if (BigInt.from(q.read<int>('received')) + BigInt.from(l.quantityAtomic) >
              BigInt.from(original.quantityAtomic) &&
          !l.overageAcknowledged) {
        throw StateError('El exceso requiere revisión explícita.');
      }
    }
    await db
        .into(db.supplierReceipts)
        .insert(
          SupplierReceiptsCompanion.insert(
            id: p.receiptId,
            orderId: p.orderId,
            eventId: e.eventId,
            intentHash: hash,
            baseEventId: p.baseEventId,
            occurredAtMs: p.occurredAtMs,
            totalMinor: p.totalMinor,
            createdEventId: Value(e.eventId),
            lastEventId: Value(e.eventId),
            lastServerSequence: Value(e.serverSequence),
          ),
        );
    final touched = <String>{};
    for (final l in p.items) {
      final original = current.document.items.singleWhere(
        (o) => o.id == l.orderItemId,
      );
      final balance =
          await (db.select(db.inventoryBalances)..where(
                (b) => b.inventoryItemId.equals(original.inventoryItemId),
              ))
              .getSingle();
      int add(int value, int delta) {
        final n = BigInt.from(value) + BigInt.from(delta);
        if (n.abs() > BigInt.from(9007199254740991)) {
          throw StateError('Saldo fuera de rango.');
        }
        return n.toInt();
      }

      await db
          .into(db.inventoryMovements)
          .insert(
            InventoryMovementsCompanion.insert(
              movementId: l.movementId,
              inventoryItemId: original.inventoryItemId,
              eventId: e.eventId,
              movementType: 'stock_receipt',
              quantityDeltaAtomic: l.quantityAtomic,
              createdAtLocal: e.createdAtLocal,
              serverSequence: Value(e.serverSequence),
            ),
          );
      await (db.update(db.inventoryBalances)
            ..where((b) => b.inventoryItemId.equals(original.inventoryItemId)))
          .write(
            InventoryBalancesCompanion(
              quantityOnHandAtomic: Value(
                add(balance.quantityOnHandAtomic, l.quantityAtomic),
              ),
              quantityAvailableAtomic: Value(
                add(balance.quantityAvailableAtomic, l.quantityAtomic),
              ),
              version: Value(
                balance.version +
                    (touched.add(original.inventoryItemId) ? 1 : 0),
              ),
              lastEventId: Value(e.eventId),
              lastServerSequence: Value(
                e.serverSequence ?? balance.lastServerSequence,
              ),
            ),
          );
      // The movement identity also names the immutable receipt line in its own table.
      await db
          .into(db.supplierReceiptItems)
          .insert(
            SupplierReceiptItemsCompanion.insert(
              id: l.movementId,
              receiptId: p.receiptId,
              orderId: p.orderId,
              orderItemId: l.orderItemId,
              quantityAtomic: l.quantityAtomic,
              actualPriceMinor: l.actualPriceMinor,
              totalMinor: l.totalMinor,
              movementId: l.movementId,
            ),
          );
    }
    await _advanceHead(e, await _receiptStatus(p.orderId));
  });

  @override
  Future<void> closeRemainder(SyncEvent e, SupplierOrderClosedPayload p) =>
      db.transaction(() async {
        final current = (await find(p.orderId))!;
        if (current.status != 'partial') {
          throw StateError('Solo un pedido parcial permite cerrar faltantes.');
        }
        final pending = {
          for (final q in await _quantities(p.orderId))
            if (q.read<int>('quantity_atomic') > q.read<int>('received'))
              q.read<String>('id'):
                  q.read<int>('quantity_atomic') - q.read<int>('received'),
        };
        if (p.items.length != pending.length ||
            p.items.any(
              (l) => pending[l.orderItemId] != l.closedQuantityAtomic,
            )) {
          throw StateError(
            'El cierre debe acreditar exactamente todo el remanente.',
          );
        }
        for (final l in p.items) {
          await (db.update(
            db.supplierOrderItems,
          )..where((t) => t.id.equals(l.orderItemId))).write(
            SupplierOrderItemsCompanion(
              closedQuantityAtomic: Value(l.closedQuantityAtomic),
            ),
          );
        }
        await _advanceHead(e, 'closed');
      });

  @override
  Future<void> acknowledgeEffects(SyncEvent e) async {
    final seq = e.serverSequence;
    if (seq == null) return;
    await db.customUpdate(
      'UPDATE supplier_receipts SET last_server_sequence=? WHERE event_id=?',
      variables: [Variable(seq), Variable(e.eventId)],
      updates: {db.supplierReceipts},
    );
    await db.customUpdate(
      'UPDATE inventory_movements SET server_sequence=? WHERE event_id=?',
      variables: [Variable(seq), Variable(e.eventId)],
      updates: {db.inventoryMovements},
    );
    await db.customUpdate(
      'UPDATE inventory_balances SET last_server_sequence=? WHERE last_event_id=?',
      variables: [Variable(seq), Variable(e.eventId)],
      updates: {db.inventoryBalances},
    );
  }

  Future<void> _restoreReceipt(SyncEvent e) async {
    final receipts = await (db.select(
      db.supplierReceipts,
    )..where((r) => r.eventId.equals(e.eventId))).get();
    for (final r in receipts) {
      await (db.delete(
        db.supplierReceiptItems,
      )..where((l) => l.receiptId.equals(r.id))).go();
      await (db.delete(
        db.supplierReceipts,
      )..where((l) => l.id.equals(r.id))).go();
    }
    final movements = await (db.select(
      db.inventoryMovements,
    )..where((m) => m.eventId.equals(e.eventId))).get();
    final touched = <String>{};
    for (final m in movements) {
      final b = await (db.select(
        db.inventoryBalances,
      )..where((b) => b.inventoryItemId.equals(m.inventoryItemId))).getSingle();
      // Delta subtraction preserves intervening sales and independent successors.
      final hand =
          BigInt.from(b.quantityOnHandAtomic) -
          BigInt.from(m.quantityDeltaAtomic);
      final available =
          BigInt.from(b.quantityAvailableAtomic) -
          BigInt.from(m.quantityDeltaAtomic);
      if (hand.abs() > BigInt.from(9007199254740991) ||
          available.abs() > BigInt.from(9007199254740991)) {
        throw StateError(
          'Restauración requiere resolver saldo fuera de rango.',
        );
      }
      await (db.delete(
        db.inventoryMovements,
      )..where((t) => t.movementId.equals(m.movementId))).go();
      final previous = await db
          .customSelect(
            '''SELECT event_id,server_sequence FROM (
              SELECT event_id,server_sequence,rowid ordinal FROM inventory_movements WHERE inventory_item_id=?
              UNION ALL SELECT i.created_event_id,e.server_sequence,-1 ordinal FROM inventory_items i
                LEFT JOIN events e ON e.event_id=i.created_event_id WHERE i.id=? AND i.created_event_id IS NOT NULL
            ) ORDER BY ordinal DESC LIMIT 1''',
            variables: [
              Variable(m.inventoryItemId),
              Variable(m.inventoryItemId),
            ],
          )
          .getSingleOrNull();
      if (b.lastEventId == e.eventId && previous == null) {
        throw StateError(
          'No se pudo acreditar la procedencia anterior del saldo; requiere resolución explícita.',
        );
      }
      await (db.update(
        db.inventoryBalances,
      )..where((t) => t.inventoryItemId.equals(m.inventoryItemId))).write(
        InventoryBalancesCompanion(
          quantityOnHandAtomic: Value(hand.toInt()),
          quantityAvailableAtomic: Value(available.toInt()),
          version: Value(b.version - (touched.add(m.inventoryItemId) ? 1 : 0)),
          lastEventId: b.lastEventId == e.eventId && previous != null
              ? Value(previous.read<String>('event_id'))
              : const Value.absent(),
          lastServerSequence: b.lastEventId == e.eventId
              ? Value(previous?.readNullable<int>('server_sequence'))
              : const Value.absent(),
        ),
      );
    }
  }

  DriftSyncPersistence get history => DriftSyncPersistence(
    db: db,
    eventDao: db.eventDao,
    eventRefDao: db.eventRefDao,
    syncCheckpointDao: db.syncCheckpointDao,
  );
  @override
  Future<SyncEvent?> eventById(String id) => history.eventById(id);
  @override
  Future<SupplierOrderProjection?> find(String id) async {
    final head = await (db.select(
      db.supplierOrders,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (head == null) return null;
    final items =
        await (db.select(db.supplierOrderItems)
              ..where((t) => t.orderId.equals(id))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();
    return SupplierOrderProjection(
      document: SupplierOrderDraftSavedPayload.fromJson({
        'contract_version': 1,
        'order_id': id,
        'base_event_id': null,
        'supplier_id': head.supplierId,
        'supplier_name_snapshot': head.supplierNameSnapshot,
        'supplier_phone_snapshot': head.supplierPhoneSnapshot,
        'currency': head.currency,
        'occurred_at_ms': head.occurredAtMs,
        'notes': head.notes,
        'total_minor': head.totalMinor,
        'items': items
            .map(
              (l) => {
                'id': l.id,
                'variant_id': l.variantId,
                'inventory_item_id': l.inventoryItemId,
                'unit_id': l.unitId,
                'product_name_snapshot': l.productNameSnapshot,
                'variant_name_snapshot': l.variantNameSnapshot,
                'dimension': l.dimension,
                'unit_code_snapshot': l.unitCodeSnapshot,
                'unit_symbol_snapshot': l.unitSymbolSnapshot,
                'unit_atomic_factor': l.unitAtomicFactor,
                'reference_quantity_atomic': l.referenceQuantityAtomic,
                'quantity_atomic': l.quantityAtomic,
                'quoted_price_minor': l.quotedPriceMinor,
                'total_minor': l.totalMinor,
              },
            )
            .toList(),
      }),
      status: head.status,
      version: head.version,
      createdEventId: head.createdEventId,
      lastEventId: head.lastEventId,
      lastServerSequence: head.lastServerSequence,
    );
  }

  @override
  Future<bool> hasReceipts(String id) async =>
      (await (db.select(db.supplierReceipts)
                ..where((t) => t.orderId.equals(id))
                ..limit(1))
              .get())
          .isNotEmpty;
  @override
  Future<void> acknowledge(String id, int sequence) async {
    await db.customUpdate(
      'UPDATE supplier_orders SET last_server_sequence = ? WHERE id = ? AND (last_server_sequence IS NULL OR last_server_sequence < ?)',
      variables: [Variable(sequence), Variable(id), Variable(sequence)],
      updates: {db.supplierOrders},
    );
  }

  @override
  Future<void> validateLineIdentities(
    SyncEvent event,
    List<SupplierOrderLine> lines,
  ) async {
    final rows = await db
        .customSelect(
          '''SELECT e.aggregate_id,json_extract(l.value,'\$.id') line_id,
      json_extract(l.value,'\$.variant_id') variant_id FROM events e,json_each(e.payload,'\$.items') l
      WHERE e.aggregate_type='supplier_order' AND e.event_id<>? AND e.delivery_status NOT IN ('rejected','conflict')
        AND json_extract(l.value,'\$.id') IN (${lines.map((_) => '?').join(',')})''',
          variables: [
            Variable(event.eventId),
            ...lines.map((l) => Variable(l.id)),
          ],
        )
        .get();
    final identities = {for (final line in lines) line.id: line.variantId};
    if (rows.any(
      (r) =>
          r.read<String>('aggregate_id') != event.aggregateId ||
          identities[r.read<String>('line_id')] != r.read<String>('variant_id'),
    )) {
      throw StateError(
        'Una identidad de partida ya pertenece a otra variante o pedido histórico.',
      );
    }
  }

  @override
  Future<void> write(SupplierOrderProjection order) => db.transaction(() async {
    final p = order.document;
    final values = <String, Object?>{
      'id': p.orderId,
      'supplier_id': p.supplierId,
      'status': order.status,
      'occurred_at_ms': p.occurredAtMs,
      'currency': p.currency,
      'supplier_name_snapshot': p.supplierNameSnapshot,
      'supplier_phone_snapshot': p.supplierPhoneSnapshot,
      'notes': p.notes,
      'total_minor': p.totalMinor,
      'active': 1,
      'version': order.version,
      'created_event_id': order.createdEventId,
      'last_event_id': order.lastEventId,
      'last_server_sequence': order.lastServerSequence,
    };
    await db.customUpdate(
      'INSERT INTO supplier_orders (${values.keys.join(',')}) VALUES (${values.keys.map((_) => '?').join(',')}) ON CONFLICT(id) DO UPDATE SET ${values.keys.where((k) => k != 'id').map((k) => '$k = excluded.$k').join(',')}',
      variables: values.values.map(_variable).toList(),
      updates: {db.supplierOrders},
    );
    // Solo borradores cambian hijos; cancelar nunca destruye snapshots ni vínculos.
    if (!{'draft', 'confirmed'}.contains(order.status)) return;
    await (db.delete(
      db.supplierOrderItems,
    )..where((t) => t.orderId.equals(p.orderId))).go();
    for (var i = 0; i < p.items.length; i++) {
      final l = p.items[i];
      final v = {
        ...l.toJson(),
        'order_id': p.orderId,
        'closed_quantity_atomic': 0,
        'position': i,
      };
      await db.customUpdate(
        'INSERT INTO supplier_order_items (${v.keys.join(',')}) VALUES (${v.keys.map((_) => '?').join(',')})',
        variables: v.values.map(_variable).toList(),
        updates: {db.supplierOrderItems},
      );
    }
  });
  Variable _variable(Object? v) =>
      v is int ? Variable<int>(v) : Variable<String>(v as String?);
  @override
  Future<void> restore(SyncEvent event) => db.transaction(() async {
    final current = await find(event.aggregateId);
    if (current?.lastEventId != event.eventId) return;
    final op = SupplierOrderOperation.decode(event);
    if (op.baseEventId == null) {
      await (db.delete(
        db.supplierOrderItems,
      )..where((t) => t.orderId.equals(event.aggregateId))).go();
      await (db.delete(
        db.supplierOrders,
      )..where((t) => t.id.equals(event.aggregateId))).go();
      return;
    }
    final base = await eventById(op.baseEventId!);
    if (base == null) {
      throw StateError('Falta la base para recuperar el pedido.');
    }
    if (event.eventType == SupplierReceiptConfirmedPayload.eventType) {
      await _restoreReceipt(event);
    } else if (event.eventType == SupplierOrderClosedPayload.eventType) {
      await (db.update(
        db.supplierOrderItems,
      )..where((t) => t.orderId.equals(event.aggregateId))).write(
        const SupplierOrderItemsCompanion(closedQuantityAtomic: Value(0)),
      );
    }
    final previous = SupplierOrderOperation.decode(base);
    var documentBase = base;
    var documentOp = previous;
    while (documentOp.document == null) {
      documentBase = (await eventById(documentOp.baseEventId!))!;
      documentOp = SupplierOrderOperation.decode(documentBase);
    }
    final priorStatus = previous.status == 'receipt'
        ? await _receiptStatus(event.aggregateId)
        : previous.status;
    final restoreHead =
        {
          SupplierReceiptConfirmedPayload.eventType,
          SupplierOrderClosedPayload.eventType,
        }.contains(event.eventType)
        ? _restoreHead
        : write;
    await restoreHead(
      SupplierOrderProjection(
        document: documentOp.document!,
        status: priorStatus,
        version: event.baseVersion!,
        createdEventId: current!.createdEventId,
        lastEventId: base.eventId,
        lastServerSequence: base.serverSequence ?? event.baseServerSequence,
      ),
    );
  });
  static const catalogSql =
      '''SELECT p.id product_id,p.name product_name,p.last_event_id product_event,
    p.sale_mode,p.price_reference_quantity_atomic,v.id variant_id,v.name variant_name,
    v.current_supplier_id,v.target_stock_atomic,i.id inventory_item_id,i.last_event_id item_event,
    u.unit_id,u.code unit_code,u.symbol unit_symbol,u.dimension,u.atomic_factor,
    s.id supplier_id,s.name supplier_name,s.phone supplier_phone,s.last_event_id supplier_event,
    vs.quoted_price_minor,vs.quoted_at_ms,coalesce(b.quantity_on_hand_atomic,0) balance_atomic,
    b.last_event_id balance_event
    FROM product_variants v JOIN products p ON p.id=v.product_id
    JOIN inventory_items i ON i.id=v.inventory_item_id
    JOIN units u ON u.unit_id=i.default_unit_id
    JOIN variant_suppliers vs ON vs.variant_id=v.id
    JOIN suppliers s ON s.id=vs.supplier_id
    LEFT JOIN inventory_balances b ON b.inventory_item_id=i.id
    WHERE p.active=1 AND v.active=1 AND i.active=1 AND u.active=1 AND s.active=1
      AND NOT EXISTS (SELECT 1 FROM recipe_components rc WHERE rc.variant_id=v.id)
      AND (p.sale_mode='unit' AND u.dimension='count' OR
        p.sale_mode='measured' AND (SELECT dimension FROM units su WHERE su.unit_id=p.sale_unit_id)=u.dimension AND u.dimension IN ('mass','volume'))
    ORDER BY s.name,p.name,v.sort_order''';
  @override
  Future<List<ReplenishmentCandidate>> candidates() async {
    final rows = await db.customSelect(catalogSql).get();
    // Dos consultas agrupadas, independientes del número de variantes/proveedores.
    final pending = await db.customSelect(
      '''WITH received AS (
      SELECT order_item_id, sum(quantity_atomic) qty FROM supplier_receipt_items GROUP BY order_item_id)
      SELECT l.variant_id,l.quantity_atomic,l.closed_quantity_atomic,coalesce(r.qty,0) received
      FROM supplier_order_items l JOIN supplier_orders o ON o.id=l.order_id
      LEFT JOIN received r ON r.order_item_id=l.id WHERE o.status IN ('confirmed','partial')''',
    ).get();
    final totals = <String, BigInt>{};
    for (final l in pending) {
      final amount =
          BigInt.from(l.read<int>('quantity_atomic')) -
          BigInt.from(l.read<int>('closed_quantity_atomic')) -
          BigInt.from(l.read<int>('received'));
      final id = l.read<String>('variant_id');
      totals[id] =
          (totals[id] ?? BigInt.zero) +
          (amount.isNegative ? BigInt.zero : amount);
    }
    return rows.map((row) {
      final j = row.data;
      final pendingAmount = totals[j['variant_id']] ?? BigInt.zero;
      if (pendingAmount > BigInt.from(9007199254740991)) {
        throw StateError('Pendiente fuera de rango.');
      }
      final basis = jsonEncode({...j, 'pending_atomic': pendingAmount.toInt()});
      return ReplenishmentCandidate(
        productId: j['product_id'] as String,
        variantId: j['variant_id'] as String,
        productName: j['product_name'] as String,
        variantName: j['variant_name'] as String?,
        inventoryItemId: j['inventory_item_id'] as String,
        unitId: j['unit_id'] as String,
        unitCode: j['unit_code'] as String,
        unitSymbol: j['unit_symbol'] as String,
        dimension: j['dimension'] as String,
        atomicFactor: j['atomic_factor'] as int,
        referenceAtomic: j['sale_mode'] == 'unit'
            ? 1
            : j['price_reference_quantity_atomic'] as int,
        supplierId: j['supplier_id'] as String,
        supplierName: j['supplier_name'] as String,
        supplierPhone: j['supplier_phone'] as String?,
        currentSupplierId: j['current_supplier_id'] as String?,
        targetAtomic: j['target_stock_atomic'] as int?,
        balanceAtomic: j['balance_atomic'] as int,
        pendingAtomic: pendingAmount.toInt(),
        priceMinor: j['quoted_price_minor'] as int,
        basis: basis,
      );
    }).toList();
  }
}
