import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'recovery_snapshot.dart';
import 'recovery_json.dart';
import '../sync/supplier_intent.dart';
import '../sync/payloads/supplier_order_draft_saved_payload.dart';
import '../sync/payloads/supplier_order_confirmed_payload.dart';
import '../sync/payloads/supplier_order_cancelled_payload.dart';
import '../sync/payloads/supplier_receipt_confirmed_payload.dart';
import '../sync/payloads/supplier_order_closed_payload.dart';

class RecoverySupplierOrderValidator {
  static void validate(RecoverySnapshot snapshot) {
    void check(bool ok) {
      if (!ok) {
        throw StateError(
          'Historia/proyección de pedido o recepción incoherente.',
        );
      }
    }

    void compare(Map<String, Object?>? row, Map<String, Object?> expected) {
      check(row != null);
      for (final e in expected.entries) {
        check(recoveryCanonical(row![e.key]) == recoveryCanonical(e.value));
      }
    }

    final seenReceipts = <String>{};
    for (final row in snapshot.rows('supplier_orders')) {
      final id = row['id'] as String;
      final chain = <Map<String, Object?>>[];
      var cursor = row['last_event_id'] as String?;
      final seen = <String>{};
      while (cursor != null) {
        check(seen.add(cursor));
        final event = snapshot.event(cursor);
        check(
          event != null &&
              event['aggregate_type'] == 'supplier_order' &&
              event['aggregate_id'] == id,
        );
        chain.add(event!);
        final json = jsonDecode(event['payload'] as String) as Map;
        cursor = json['base_event_id'] as String?;
      }
      SupplierOrderDraftSavedPayload? doc;
      var state = '';
      final received = <String, int>{}, closed = <String, int>{};
      var version = 0;
      for (final e in chain.reversed) {
        final json = jsonDecode(e['payload'] as String);
        check(e['base_version'] == (version == 0 ? 1 : version));
        version++;
        final type = e['event_type'];
        if (type == SupplierReceiptConfirmedPayload.eventType) {
          check(state == 'confirmed' || state == 'partial');
          final p = SupplierReceiptConfirmedPayload.fromJson(json);
          check(seenReceipts.add(p.receiptId));
          final receiptRows = snapshot
              .relatedRows('supplier_receipts', 'order_id', id)
              .where((r) => r['id'] == p.receiptId)
              .toList();
          check(receiptRows.length == 1);
          compare(receiptRows.single, {
            'id': p.receiptId,
            'order_id': id,
            'event_id': e['event_id'],
            'base_event_id': p.baseEventId,
            'intent_hash': sha256
                .convert(utf8.encode(supplierIntent(p.toJson())))
                .toString(),
            'occurred_at_ms': p.occurredAtMs,
            'total_minor': p.totalMinor,
            'active': 1,
            'version': 1,
            'created_event_id': e['event_id'],
            'last_event_id': e['event_id'],
            'last_server_sequence': e['server_sequence'],
          });
          final lines = snapshot
              .relatedRows('supplier_receipt_items', 'receipt_id', p.receiptId)
              .toList();
          check(lines.length == p.items.length);
          for (final item in p.items) {
            final original = doc!.items.singleWhere(
              (l) => l.id == item.orderItemId,
            );
            check(
              original.referenceQuantityAtomic == item.referenceQuantityAtomic,
            );
            final qty = (received[item.orderItemId] ?? 0) + item.quantityAtomic;
            check(
              qty <= 9007199254740991 &&
                  (qty <= original.quantityAtomic || item.overageAcknowledged),
            );
            received[item.orderItemId] = qty;
            compare(
              lines.singleWhere((l) => l['order_item_id'] == item.orderItemId),
              {
                'id': item.movementId,
                'receipt_id': p.receiptId,
                'order_id': id,
                'order_item_id': item.orderItemId,
                'movement_id': item.movementId,
                'quantity_atomic': item.quantityAtomic,
                'actual_price_minor': item.actualPriceMinor,
                'total_minor': item.totalMinor,
              },
            );
            final movements = snapshot
                .relatedRows(
                  'inventory_movements',
                  'event_id',
                  e['event_id'] as String,
                )
                .where((m) => m['movement_id'] == item.movementId)
                .toList();
            check(movements.length == 1);
            compare(movements.single, {
              'inventory_item_id': original.inventoryItemId,
              'event_id': e['event_id'],
              'movement_type': 'stock_receipt',
              'quantity_delta_atomic': item.quantityAtomic,
              'total_cost_minor': null,
              'sale_item_id': null,
              'sale_adjustment_id': null,
              'reversal_of_movement_id': null,
              'reason': null,
              'server_sequence': e['server_sequence'],
              'created_at_local': e['created_at_local'],
            });
          }
          state =
              doc!.items.every((l) => (received[l.id] ?? 0) >= l.quantityAtomic)
              ? 'received'
              : 'partial';
        } else if (type == SupplierOrderClosedPayload.eventType) {
          check(state == 'partial');
          final p = SupplierOrderClosedPayload.fromJson(json);
          final pending = {
            for (final l in doc!.items)
              if (l.quantityAtomic > (received[l.id] ?? 0))
                l.id: l.quantityAtomic - (received[l.id] ?? 0),
          };
          check(p.items.length == pending.length);
          for (final item in p.items) {
            check(pending[item.orderItemId] == item.closedQuantityAtomic);
            closed[item.orderItemId] = item.closedQuantityAtomic;
          }
          state = 'closed';
        } else if (type == SupplierOrderCancelledPayload.eventType) {
          SupplierOrderCancelledPayload.fromJson(json);
          check(state == 'draft' || state == 'confirmed');
          state = 'cancelled';
        } else {
          check(state == '' || state == 'draft');
          check(
            type == SupplierOrderDraftSavedPayload.eventType ||
                type == SupplierOrderConfirmedPayload.eventType,
          );
          final next = SupplierOrderDraftSavedPayload.fromJson(json);
          check(doc == null || doc.supplierId == next.supplierId);
          doc = next;
          state = type == SupplierOrderConfirmedPayload.eventType
              ? 'confirmed'
              : 'draft';
        }
      }
      check(row['last_server_sequence'] == chain.first['server_sequence']);
      check(
        doc != null &&
            row['status'] == state &&
            row['version'] == version &&
            row['created_event_id'] == chain.last['event_id'],
      );
      compare(row, {
        for (final e in doc!.toJson().entries)
          if (!{
            'contract_version',
            'base_event_id',
            'order_id',
            'items',
          }.contains(e.key))
            e.key: e.value,
      });
      final lines =
          snapshot.relatedRows('supplier_order_items', 'order_id', id).toList()
            ..sort(
              (a, b) => (a['position'] as int).compareTo(b['position'] as int),
            );
      check(lines.length == doc.items.length);
      for (var i = 0; i < lines.length; i++) {
        compare(lines[i], {
          ...doc.items[i].toJson(),
          'position': i,
          'closed_quantity_atomic': closed[doc.items[i].id] ?? 0,
        });
      }
    }
    check(
      snapshot
          .rows('supplier_receipts')
          .every((r) => seenReceipts.contains(r['id'])),
    );
  }
}
