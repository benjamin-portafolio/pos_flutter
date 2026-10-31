import 'inventory_movement_payload.dart';
import 'sale_item_snapshot.dart';

/// Estado absoluto antes/después; incluye todas las líneas activas en su orden.
class TarifaVentaBorradorCambiadaPayload {
  TarifaVentaBorradorCambiadaPayload({
    required this.previousMode,
    required this.pricingMode,
    required this.expectedDraftEventId,
    required this.previousTotalMinor,
    required this.totalMinor,
    required List<
      ({
        String id,
        int sortOrder,
        SaleItemSnapshot before,
        SaleItemSnapshot after,
      })
    >
    lines,
  }) : lines = List.unmodifiable(lines) {
    if (!['normal', 'offer'].contains(previousMode) ||
        !['normal', 'offer'].contains(pricingMode) ||
        previousMode == pricingMode ||
        previousTotalMinor < 0 ||
        totalMinor < 0 ||
        totalMinor > SaleItemSnapshot.maxInteger ||
        previousTotalMinor > SaleItemSnapshot.maxInteger ||
        lines.map((l) => l.id).toSet().length != lines.length) {
      throw const FormatException('Cambio de tarifa inválido.');
    }
    if (expectedDraftEventId != null) {
      InventoryMovementPayload.requiredUuidV4(
        expectedDraftEventId!,
        'expected_draft_event_id',
      );
    }
    var beforeTotal = BigInt.zero, afterTotal = BigInt.zero;
    var order = -1;
    for (final l in lines) {
      InventoryMovementPayload.requiredUuidV4(l.id, 'sale_item_id');
      if (l.sortOrder <= order ||
          l.sortOrder > SaleItemSnapshot.maxInteger ||
          !l.before.sameConditions(l.before.withPricingMode(previousMode)) ||
          !l.before.withPricingMode(pricingMode).sameConditions(l.after) ||
          l.before.quantity != l.after.quantity ||
          l.before.measuredQuantityAtomic != l.after.measuredQuantityAtomic) {
        throw const FormatException('Condiciones de tarifa incoherentes.');
      }
      order = l.sortOrder;
      beforeTotal += BigInt.from(l.before.totalMinor);
      afterTotal += BigInt.from(l.after.totalMinor);
    }
    if (beforeTotal != BigInt.from(previousTotalMinor) ||
        afterTotal != BigInt.from(totalMinor)) {
      throw const FormatException('Totales de tarifa incoherentes.');
    }
  }
  static const aggregateType = 'sale_draft';
  static const eventType = 'tarifa_venta_borrador_cambiada';
  final String previousMode, pricingMode;
  final String? expectedDraftEventId;
  final int previousTotalMinor, totalMinor;
  final List<
    ({
      String id,
      int sortOrder,
      SaleItemSnapshot before,
      SaleItemSnapshot after,
    })
  >
  lines;
  int get amountChangedLines =>
      lines.where((l) => l.before.totalMinor != l.after.totalMinor).length;
  int get sourceOnlyChangedLines => lines
      .where(
        (l) =>
            l.before.totalMinor == l.after.totalMinor &&
            l.before.effectivePriceSource != l.after.effectivePriceSource,
      )
      .length;
  int get withoutOfferLines =>
      lines.where((l) => l.before.offerPriceMinorSnapshot == null).length;

  Map<String, Object?> toJson() => {
    'previous_mode': previousMode,
    'pricing_mode': pricingMode,
    'expected_draft_event_id': expectedDraftEventId,
    'previous_total_minor': previousTotalMinor,
    'total_minor': totalMinor,
    'lines': [
      for (final l in lines)
        {
          'sale_item_id': l.id,
          'sort_order': l.sortOrder,
          'before': l.before.toJson(),
          'after': l.after.toJson(),
        },
    ],
  };
  factory TarifaVentaBorradorCambiadaPayload.fromJson(Map<String, Object?> j) =>
      TarifaVentaBorradorCambiadaPayload(
        previousMode: j['previous_mode'] as String,
        pricingMode: j['pricing_mode'] as String,
        expectedDraftEventId: j['expected_draft_event_id'] as String?,
        previousTotalMinor: j['previous_total_minor'] as int,
        totalMinor: j['total_minor'] as int,
        lines: [
          for (final raw in j['lines'] as List)
            (
              id: (raw as Map)['sale_item_id'] as String,
              sortOrder: raw['sort_order'] as int,
              before: SaleItemSnapshot.fromJson(
                Map<String, Object?>.from(raw['before'] as Map),
              ),
              after: SaleItemSnapshot.fromJson(
                Map<String, Object?>.from(raw['after'] as Map),
              ),
            ),
        ],
      );
}
