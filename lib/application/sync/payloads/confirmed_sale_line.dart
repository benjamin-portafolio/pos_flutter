import 'inventory_movement_payload.dart';
import 'sale_consumption.dart';
import 'sale_item_snapshot.dart';

class ConfirmedSaleLine {
  ConfirmedSaleLine({
    required this.id,
    required this.productId,
    required this.configurationEventId,
    required this.snapshot,
    required this.consumptionMode,
    required this.saleUnitId,
    required List<SaleConsumption> consumptions,
  }) : consumptions = List.unmodifiable(consumptions) {
    for (final value in [
      id,
      productId,
      configurationEventId,
      snapshot.variantId,
    ]) {
      InventoryMovementPayload.requiredUuidV4(value, 'line identity');
    }
    if ((snapshot.saleMode == 'measured') != (saleUnitId != null)) {
      throw const FormatException('Unidad de venta inválida.');
    }
    if (saleUnitId != null) {
      InventoryMovementPayload.requiredUuidV4(saleUnitId!, 'sale_unit_id');
    }
    if (!['none', 'direct', 'recipe'].contains(consumptionMode) ||
        (consumptionMode == 'none' && consumptions.isNotEmpty) ||
        (consumptionMode == 'direct' &&
            (consumptions.length != 1 ||
                consumptions.single.componentAtomic != 1)) ||
        (consumptionMode == 'recipe' && consumptions.isEmpty) ||
        consumptions.map((c) => c.inventoryItemId).toSet().length !=
            consumptions.length) {
      throw const FormatException('Configuración de consumo inválida.');
    }
    for (final c in consumptions) {
      final expected = SaleConsumption.rounded(
        c.componentAtomic,
        snapshot.quantity ?? snapshot.measuredQuantityAtomic!,
        consumptionMode == 'recipe'
            ? snapshot.priceReferenceQuantityAtomic ?? 1
            : 1,
      );
      if (c.deltaAtomic != -expected) {
        throw const FormatException('Delta inconsistente.');
      }
    }
  }
  final String id, productId, configurationEventId, consumptionMode;
  final String? saleUnitId;
  final SaleItemSnapshot snapshot;
  final List<SaleConsumption> consumptions;
  Map<String, Object?> toJson() => {
    'sale_item_id': id,
    'product_id': productId,
    'configuration_event_id': configurationEventId,
    'snapshot': snapshot.toJson(),
    'consumption_mode': consumptionMode,
    'sale_unit_id': saleUnitId,
    'consumptions': consumptions.map((c) => c.toJson()).toList(),
  };
  factory ConfirmedSaleLine.fromJson(Map<String, Object?> j) =>
      ConfirmedSaleLine(
        id: j['sale_item_id'] as String,
        productId: j['product_id'] as String,
        configurationEventId: j['configuration_event_id'] as String,
        snapshot: SaleItemSnapshot.fromJson(
          Map<String, Object?>.from(j['snapshot'] as Map),
        ),
        consumptionMode: j['consumption_mode'] as String,
        saleUnitId: j['sale_unit_id'] as String?,
        consumptions: (j['consumptions'] as List)
            .map(
              (c) =>
                  SaleConsumption.fromJson(Map<String, Object?>.from(c as Map)),
            )
            .toList(),
      );
}
