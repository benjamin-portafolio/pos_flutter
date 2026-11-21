import '../../../../domain/inventario/inventory_quantity_codec.dart';
import '../../../../application/sync/payloads/supplier_order_draft_saved_payload.dart';
import '../../../../application/sync/payloads/supplier_order_line.dart';
import '../../../../application/sync/payloads/supplier_order_json.dart';
import '../../../../domain/proveedores/replenishment_candidate.dart';
import '../../../../domain/inventario/unidad_inventario.dart';
import '../../../../domain/inventario/dimension_unidad.dart';

SupplierOrderLine candidateLine(
  ReplenishmentCandidate c,
  String id,
  int quantity,
) => SupplierOrderLine.fromJson({
  'id': id,
  'variant_id': c.variantId,
  'inventory_item_id': c.inventoryItemId,
  'unit_id': c.unitId,
  'product_name_snapshot': c.productName,
  'variant_name_snapshot': c.variantName,
  'dimension': c.dimension,
  'unit_code_snapshot': c.unitCode,
  'unit_symbol_snapshot': c.unitSymbol,
  'unit_atomic_factor': c.atomicFactor,
  'reference_quantity_atomic': c.referenceAtomic,
  'quantity_atomic': quantity,
  'quoted_price_minor': c.priceMinor,
  'total_minor': orderAmount(c.priceMinor, quantity, c.referenceAtomic),
});
SupplierOrderDraftSavedPayload orderDocument({
  required String id,
  required String? base,
  required String supplierId,
  required String name,
  required String? phone,
  required String currency,
  required List<SupplierOrderLine> items,
  String? notes,
  required int occurredAtMs,
}) => SupplierOrderDraftSavedPayload.fromJson({
  'contract_version': 1,
  'order_id': id,
  'base_event_id': base,
  'supplier_id': supplierId,
  'supplier_name_snapshot': name,
  'supplier_phone_snapshot': phone,
  'currency': currency,
  'occurred_at_ms': occurredAtMs,
  'notes': notes,
  'items': items.map((l) => l.toJson()).toList(),
  'total_minor': orderTotal(items.map((l) => l.totalMinor)),
});
UnidadInventario lineUnit(SupplierOrderLine l) => UnidadInventario(
  id: l.unitId,
  code: l.unitCodeSnapshot,
  nombre: l.unitCodeSnapshot,
  simbolo: l.unitSymbolSnapshot,
  dimension: DimensionUnidad.fromCode(l.dimension),
  factorAtomico: l.unitAtomicFactor,
  maximosDecimales: l.dimension == 'count' ? 0 : 9,
  activa: true,
);
String orderMoney(int? value) => value == null
    ? 'Sin precio conocido'
    : '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';

UnidadInventario candidateUnit(ReplenishmentCandidate c) => UnidadInventario(
  id: c.unitId,
  code: c.unitCode,
  nombre: c.unitCode,
  simbolo: c.unitSymbol,
  dimension: DimensionUnidad.fromCode(c.dimension),
  factorAtomico: c.atomicFactor,
  maximosDecimales: c.dimension == 'count' ? 0 : 9,
  activa: true,
);
String candidateQuantity(ReplenishmentCandidate c, int value) =>
    const InventoryQuantityCodec().formatAtomic(value, candidateUnit(c));
