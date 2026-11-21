import 'supplier_order_json.dart';

/// Contrato documental v1; las operaciones de pedidos se aplican en S3.
class SupplierOrderLine {
  SupplierOrderLine._(
    this.id,
    this.variantId,
    this.inventoryItemId,
    this.unitId,
    this.productNameSnapshot,
    this.variantNameSnapshot,
    this.dimension,
    this.unitCodeSnapshot,
    this.unitSymbolSnapshot,
    this.unitAtomicFactor,
    this.referenceQuantityAtomic,
    this.quantityAtomic,
    this.quotedPriceMinor,
    this.totalMinor,
  );
  final String id;
  final String variantId;
  final String inventoryItemId;
  final String unitId;
  final String productNameSnapshot;
  final String? variantNameSnapshot;
  final String dimension;
  final String unitCodeSnapshot;
  final String unitSymbolSnapshot;
  final int unitAtomicFactor;
  final int referenceQuantityAtomic;
  final int quantityAtomic;
  final int? quotedPriceMinor;
  final int? totalMinor;
  factory SupplierOrderLine.fromJson(Object? value) {
    final j = orderRecord(value);
    final p = SupplierOrderLine._(
      orderUuid(j['id']),
      orderUuid(j['variant_id']),
      orderUuid(j['inventory_item_id']),
      orderUuid(j['unit_id']),
      orderText(j['product_name_snapshot'], 160),
      j['variant_name_snapshot'] == null
          ? null
          : orderText(j['variant_name_snapshot'], 160),
      orderText(j['dimension'], 6),
      orderText(j['unit_code_snapshot'], 16),
      orderText(j['unit_symbol_snapshot'], 16),
      orderInt(j['unit_atomic_factor'], 1),
      orderInt(j['reference_quantity_atomic'], 1),
      orderInt(j['quantity_atomic'], 1),
      j['quoted_price_minor'] == null
          ? null
          : orderInt(j['quoted_price_minor']),
      j['total_minor'] == null ? null : orderInt(j['total_minor']),
    );
    if (!['count', 'mass', 'volume'].contains(p.dimension) ||
        (p.dimension == 'count' &&
            (p.unitAtomicFactor != 1 || p.referenceQuantityAtomic != 1)) ||
        (p.quotedPriceMinor == null
            ? p.totalMinor != null
            : p.totalMinor !=
                  orderAmount(
                    p.quotedPriceMinor!,
                    p.quantityAtomic,
                    p.referenceQuantityAtomic,
                  ))) {
      throw const FormatException('Unidad o importe incoherente');
    }
    return p;
  }
  Map<String, Object?> toJson() => {
    'id': id,
    'variant_id': variantId,
    'inventory_item_id': inventoryItemId,
    'unit_id': unitId,
    'product_name_snapshot': productNameSnapshot,
    'variant_name_snapshot': variantNameSnapshot,
    'dimension': dimension,
    'unit_code_snapshot': unitCodeSnapshot,
    'unit_symbol_snapshot': unitSymbolSnapshot,
    'unit_atomic_factor': unitAtomicFactor,
    'reference_quantity_atomic': referenceQuantityAtomic,
    'quantity_atomic': quantityAtomic,
    'quoted_price_minor': quotedPriceMinor,
    'total_minor': totalMinor,
  };
}
