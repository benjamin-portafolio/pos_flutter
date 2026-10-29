import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'sale_adjustment_payload.dart';
import 'sale_reconciliation_effect.dart';

/// Evidencia derivada del documento perdedor, sin reinterpretar cantidades
/// devueltas. Los movimientos físicos conservan sus IDs. Los efectos solo
/// documentales tienen un UUID determinista propio derivado del libro y origen.
class SaleReconciliationEvidence {
  static String documentaryEffectId(String operationId, String ledger) {
    final bytes = sha256
        .convert(
          utf8.encode('pos.sale-adjustment.effect.v1/$ledger/$operationId'),
        )
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static List<SaleReconciliationEffect> fromAdjustment(
    SaleAdjustmentPayload p,
  ) {
    Map<String, Object?> effect(
      String id,
      String ledger,
      String target,
      int delta,
    ) => {
      'effect_id': id,
      'ledger': ledger,
      'target_id': target,
      'delta': delta,
      'occurred_at_ms': p.occurredAtMs,
      'utc_offset_minutes': p.utcOffsetMinutes,
      'business_date': p.businessDate,
      'cash_session_id': ledger == 'cash' ? p.settlement.cash?.sessionId : null,
      'opening_event_id': ledger == 'cash'
          ? p.settlement.cash?.openingEventId
          : null,
    };
    return [
      for (final l in p.lines)
        for (final s in l.stock)
          SaleReconciliationEffect.fromJson(
            effect(s.movementId, 'stock', s.inventoryItemId, s.quantityAtomic),
          ),
      if (p.totalMinor > 0)
        SaleReconciliationEffect.fromJson(
          effect(
            p.settlement.cash?.movementId ??
                documentaryEffectId(p.operationId, p.settlement.method),
            p.settlement.method == 'cash'
                ? 'cash'
                : p.settlement.method == 'credit'
                ? 'credit'
                : 'transfer',
            p.settlement.method == 'credit'
                ? p.settlement.clienteId!
                : p.settlement.cash?.movementId ?? p.operationId,
            p.settlement.method == 'credit' ? p.totalMinor : -p.totalMinor,
          ),
        ),
    ];
  }
}
